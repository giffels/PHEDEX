package PHEDEX::Web::SQL;

=head1 NAME

PHEDEX::Web::SQL - encapsulated SQL for the web data service

=head1 SYNOPSIS

This package simply bundles SQL statements into function calls.
It's not a true object package as such, and should be inherited from by
anything that needs its methods.

=head1 DESCRIPTION

pending...

=head1 METHODS

=over

=item getLinkTasks($self)

returns a reference to an array of hashes with the following keys:
TIME_UPDATE, DEST_NODE, SRC_NODE, STATE, PRIORITY, FILES, BYTES.
Each hash represents the current amount of data queued for transfer
(has tasks) for a link given the state and priority

=over

=item *

C<$self> is an object with a DBH member which is a valid DBI database
handle. To call the routine with a bare database handle, use the 
procedural call method.

=back

=head1 SEE ALSO...

L<PHEDEX::Core::SQL|PHEDEX::Core::SQL>,

=cut

use strict;
use warnings;
use base 'PHEDEX::Core::SQL';
use Carp;
use POSIX;
use Data::Dumper;

our @EXPORT = qw( );
our (%params);
%params = ( DBH	=> undef );

sub new
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
## my $self  = ref($proto) ? $class->SUPER::new(@_) : {};
  my $self  = $class->SUPER::new(@_);

  my %args = (@_);
  map {
        $self->{$_} = defined($args{$_}) ? $args{$_} : $params{$_}
      } keys %params;
  bless $self, $class;
}

sub AUTOLOAD
{
  my $self = shift;
  my $attr = our $AUTOLOAD;
  $attr =~ s/.*:://;
  if ( exists($params{$attr}) )
  {
    $self->{$attr} = shift if @_;
    return $self->{$attr};
  }
  return unless $attr =~ /[^A-Z]/;  # skip DESTROY and all-cap methods
  my $parent = "SUPER::" . $attr;
  $self->$parent(@_);
}

sub getLinkTasks
{
    my ($self, %h) = @_;
    my ($sql,$q,@r);
    
    $sql = qq{
    select
      time_update,
      nd.name dest_node, ns.name src_node,
      state, priority,
      files, bytes
    from t_status_task xs
      join t_adm_node ns on ns.id = xs.from_node
      join t_adm_node nd on nd.id = xs.to_node
     order by nd.name, ns.name, state
 };

    $q = execute_sql( $self, $sql, () );
    while ( $_ = $q->fetchrow_hashref() ) { push @r, $_; }

    return \@r;
}

# FIXME:  %h keys should be uppercase
sub getNodes
{
    my ($self, %h) = @_;
    my ($sql,$q,%p,@r);

    $sql = qq{
        select n.name,
	       n.id,
	       n.se_name se,
	       n.kind, n.technology
          from t_adm_node n
          where 1=1
       };

    my $filters = '';
    build_multi_filters($self, \$filters, \%p, \%h,  node  => 'n.name');
    $sql .= " and ($filters)" if $filters;

    if ( $h{noempty} ) {
	$sql .= qq{ and exists (select 1 from t_dps_block_replica br where br.node = n.id and node_files != 0) };
    }

    $q = execute_sql( $self, $sql, %p );
    while ( $_ = $q->fetchrow_hashref() ) { push @r, $_; }

    return \@r;
}

# FIXME:  %h keys should be uppercase
sub getBlockReplicas
{
    my ($self, %h) = @_;
    my ($sql,$q,%p,@r);

    $sql = qq{
        select b.name block_name,
	       b.id block_id,
               b.files block_files,
               b.bytes block_bytes,
               b.is_open,
	       n.name node_name,
	       n.id node_id,
	       n.se_name se_name,
               br.node_files replica_files,
               br.node_bytes replica_bytes,
               br.time_create replica_create,
               br.time_update replica_update,
	       case when b.is_open = 'n' and
                         br.node_files = b.files
                    then 'y'
                    else 'n'
               end replica_complete,
	       br.is_custodial,
	       g.name user_group
          from t_dps_block_replica br
	  join t_dps_block b on b.id = br.block
	  join t_dps_dataset ds on ds.id = b.dataset
	  join t_adm_node n on n.id = br.node
     left join t_adm_group g on g.id = br.user_group
	 where br.node_files != 0
       };

    if (exists $h{complete}) {
	if ($h{complete} eq 'n') {
	    $sql .= qq{ and (br.node_files != b.files or b.is_open = 'y') };
	} elsif ($h{complete} eq 'y') {
	    $sql .= qq{ and br.node_files = b.files and b.is_open = 'n' };
	}
    }

    if (exists $h{custodial}) {
	if ($h{custodial} eq 'n') {
	    $sql .= qq{ and br.is_custodial = 'n' };
	} elsif ($h{custodial} eq 'y') {
	    $sql .= qq{ and br.is_custodial = 'y' };
	}
    }

    my $filters = '';
    build_multi_filters($self, \$filters, \%p, \%h, ( node  => 'n.name',
						      se    => 'n.se_name',
						      block => 'b.name',
						      group => 'g.name' ));
    $sql .= " and ($filters)" if $filters;

    if (exists $h{create_since}) {
	$sql .= ' and br.time_create >= :create_since';
	$p{':create_since'} = $h{create_since};
    }

    if (exists $h{update_since}) {
	$sql .= ' and br.time_update >= :update_since';
	$p{':update_since'} = $h{update_since};
    }

    $q = execute_sql( $self, $sql, %p );
    while ( $_ = $q->fetchrow_hashref() ) { push @r, $_; }

    return \@r;
}

sub getFileReplicas
{
    my ($self, %h) = @_;
    my ($sql,$q,%p,@r);
    
    $sql = qq{
    select b.id block_id,
           b.name block_name,
           b.files block_files,
           b.bytes block_bytes,
           b.is_open,
           f.id file_id,
           f.logical_name,
           f.filesize,
           f.checksum,
           f.time_create,
           ns.name origin_node,
           n.id node_id,
           n.name node_name,
           n.se_name se_name,
           xr.time_create replica_create,
           br.is_custodial,
           g.name user_group
    from t_dps_block b
    join t_dps_file f on f.inblock = b.id
    join t_adm_node ns on ns.id = f.node
    join t_dps_block_replica br on br.block = b.id
    left join t_adm_group g on g.id = br.user_group
    left join t_xfer_replica xr on xr.node = br.node and xr.fileid = f.id
    left join t_adm_node n on ((br.is_active = 'y' and n.id = xr.node) 
                            or (br.is_active = 'n' and n.id = br.node))
    where br.node_files != 0 
    };

    if (exists $h{complete}) {
	if ($h{complete} eq 'n') {
	    $sql .= qq{ and (br.node_files != b.files or b.is_open = 'y') };
	} elsif ($h{complete} eq 'y') {
	    $sql .= qq{ and br.node_files = b.files and b.is_open = 'n' };
	}
    }

    if (exists $h{dist_complete}) {
	if ($h{dist_complete} eq 'n') {
	    $sql .= qq{ and (b.is_open = 'y' or
			     not exists (select 1 from t_dps_block_replica br2
                                          where br2.block = b.id 
                                            and br2.node_files = b.files)) };
	} elsif ($h{dist_complete} eq 'y') {
	    $sql .= qq{ and b.is_open = 'n' 
			and exists (select 1 from t_dps_block_replica br2
                                     where br2.block = b.id 
                                       and br2.node_files = b.files) };
	}
    }

    if (exists $h{custodial}) {
	if ($h{custodial} eq 'n') {
	    $sql .= qq{ and br.is_custodial = 'n' };
	} elsif ($h{custodial} eq 'y') {
	    $sql .= qq{ and br.is_custodial = 'y' };
	}
    }

    # handle lfn
    if (exists $h{lfn}) {
        $sql .= qq { and f.logical_name = '$h{lfn}' };
    }

    my $filters = '';
    build_multi_filters($self, \$filters, \%p, \%h, ( node  => 'n.name',
						      se    => 'n.se_name',
						      block => 'b.name',
						      group => 'g.name' ));
    $sql .= " and ($filters)" if $filters;

    if (exists $h{create_since}) {
	$sql .= ' and br.time_create >= :create_since';
	$p{':create_since'} = $h{create_since};
    }

    if (exists $h{update_since}) {
	$sql .= ' and br.time_update >= :update_since';
	$p{':update_since'} = $h{update_since};
    }

    $q = execute_sql( $self, $sql, %p );
    while ( $_ = $q->fetchrow_hashref() ) { push @r, $_; }

    return \@r;
}



sub getTFC {
   my ($self, %h) = @_;
   my ($sql,$q,%p,@r);

   return [] unless $h{node};

   $sql = qq{
        select c.rule_type element_name,
	       c.protocol,
	       c.destination_match "destination-match",
               c.path_match "path-match",
               c.result_expr "result",
	       c.chain,
	       c.is_custodial,
	       c.space_token
         from t_xfer_catalogue c
	 join t_adm_node n on n.id = c.node
        where n.name = :node
        order by c.rule_index asc
    };

   $p{':node'} = $h{node};

    $q = execute_sql( $self, $sql, %p );
    while ( $_ = $q->fetchrow_hashref() ) { push @r, $_; }
   
   return \@r;
}

sub SiteDataInfo
{
  my ($core,%args) = @_;

  my $dbg = $core->{DEBUG};
  my $asearchcli = $args{ASEARCHCLI};

  my $dbh = $core->{DBH};
  $dbh->{LongTruncOk} = 1;

# get site id and name based on name pattern
  my $sql=qq(select id,name from t_adm_node where name like :sitename);
  my $sth = dbprep($dbh, $sql);
  my @handlearr=($sth,
	   ':sitename' => $args{SITENAME});
  dbbindexec(@handlearr);

  my $row = $sth->fetchrow_hashref() or die "Error: Could not resolve sitename '$args{SITENAME}'\n";

  my $nodeid = $row->{ID};
  my $fullsitename = $row->{NAME};

  print "(DBG) Site ID: $nodeid   Name: $fullsitename\n" if $dbg;

  my $sqlrowlimit=" and rownum <= $args{NUMLIMIT}" if $args{NUMLIMIT} >0;
# show all accepted requests for a node, including dataset name, where the dataset still is on the node
  $sql = qq(select distinct r.id, r.created_by, r.time_create,r.comments, rds.dataset_id, rds.name  from t_req_request r join t_req_type rt on rt.id = r.type join t_req_node rn on rn.request = r.id left join t_req_decision rd on rd.request = r.id and rd.node = rn.node join t_req_dataset rds on rds.request = r.id where rn.node = :nodeid and rt.name = 'xfer' and rd.decision = 'y' and dataset_id in (select distinct b.dataset  from t_dps_block b join t_dps_block_replica br on b.id = br.block join t_dps_dataset d on d.id = b.dataset where node = :nodeid)  $sqlrowlimit order by r.time_create desc);

  $sth = dbprep($dbh, $sql);
  @handlearr=($sth,':nodeid' => $nodeid);
  dbbindexec(@handlearr);


# prepare query to get comment texts
  $sql = qq(select comments from T_REQ_COMMENTS where id = :commentid);
  my $sth_com = dbprep($dbh, $sql);

# prepare query to get dataset stats
  $sql = qq(select name,files,bytes from t_dps_block where dataset = :datasetid);
  my $sth_stats = dbprep($dbh,$sql);

  my %dataset;
  my %requestor;
# we arrange everything in a hash sorted by dataset id and then request id
  while (my $row = $sth->fetchrow_hashref()) {
    #print Dumper($row) . "\n";
    $dataset{$row->{DATASET_ID}}{requestids}{$row->{ID}} = { requestorid => $row->{CREATED_BY},
					       commentid => $row->{COMMENTS},
					       time  => $row->{TIME_CREATE} };

    @handlearr=($sth_com,':commentid' => $row->{COMMENTS});
    dbbindexec(@handlearr);
    my $row_com = $sth_com->fetchrow_hashref();
    $dataset{$row->{DATASET_ID}}{requestids}{$row->{ID}}{comment} = $row_com->{COMMENTS};
  
    $dataset{$row->{DATASET_ID}}{name} = $row->{NAME};
    $requestor{$row->{CREATED_BY}}=undef;

    if($args{STATS}) {
      @handlearr=($sth_stats,':datasetid' => $row->{DATASET_ID});
      dbbindexec(@handlearr);
      $dataset{$row->{DATASET_ID}}{bytes}=0;
      $dataset{$row->{DATASET_ID}}{blocks}=0;
      $dataset{$row->{DATASET_ID}}{files}=0;
      while (my $row_stats = $sth_stats->fetchrow_hashref()) { # loop over blocks
        $dataset{$row->{DATASET_ID}}{bytes} += $row_stats->{BYTES};
        $dataset{$row->{DATASET_ID}}{blocks}++;
        $dataset{$row->{DATASET_ID}}{files} += $row_stats->{FILES};
      }
    }

    # for later getting a sensible order we use the latest order for this set
    $dataset{$row->{DATASET_ID}}{order} = 0 unless defined($dataset{$row->{DATASET_ID}}{order});
    $dataset{$row->{DATASET_ID}}{order} = $row->{TIME_CREATE}
      if $row->{TIME_CREATE} > $dataset{$row->{DATASET_ID}}{order};
  }

# map all requestors to names
  $sql = qq(select ident.name from t_adm_identity ident join t_adm_client cli on cli.identity = ident.id where cli.id = :requestorid);
  $sth = dbprep($dbh, $sql);
  foreach my $r (keys %requestor) {
    @handlearr=($sth,':requestorid' => $r);
    dbbindexec(@handlearr);
    my $row = $sth->fetchrow_hashref();
    $requestor{$r}=$row->{NAME};
  }

  foreach my $dsid(keys %dataset) {
    foreach my $reqid (keys %{$dataset{$dsid}{requestids}}) {
        $dataset{$dsid}{requestids}{$reqid}{requestor}=
	    $requestor{ $dataset{$dsid}{requestids}{$reqid}{requestorid} };
    }
  }

  if ($args{LOCATION}) {
    foreach my $dsid(keys %dataset) {
      my @location;
      my @output=`$asearchcli --xml --dbsInst=cms_dbs_prod_global --limit=-1 --input="find site where dataset = $dataset{$dsid}{name}"`;
      my $se;
      while (my $line = shift @output) {
        if ( (($se) = $line =~ m/<sename>(.*)<\/sename>/) ) {
	  push @location,$se;
        }
      }
      my $nreplica=$#location + 1;
      $dataset{$dsid}{replica_num}=$nreplica;
      $dataset{$dsid}{replica_loc}=join(",", sort {$a cmp $b } @location);  #unelegant, but currently for xml output
    }
  }

  return {
	   SiteDataInfo =>
  	   {
		%args,
		requestor => \%requestor,
		dataset   => \%dataset,
	   }
	 };
}

my %state_name = (
    0 => 'assigned',
    1 => 'exported',
    2 => 'transferring',
    3 => 'transferred'
    );

sub getTransferQueueStats
{
    my ($core, %h) = @_;
    my $sql = qq {
        select
            time_update,
            ns.name as "from",
            nd.name as "to",
            xs.from_node as from_id,
            xs.to_node as to_id,
            state,
            priority,
            files,
            bytes
        from
            t_status_task xs,
            t_adm_node ns,
            t_adm_node nd
        where
            ns.id = xs.from_node and
            nd.id = xs.to_node};

    if ($h{FROM})
    {
        $sql .= qq { and\n            ns.name = '$h{FROM}'};
    }

    if ($h{TO})
    {
        $sql .= qq { and\n            nd.name = '$h{TO}'};
    }
            
    $sql .= qq {\n        order by nd.name, ns.name, state};

    my @r;
    my $q = execute_sql($core, $sql);
    my %link;
    while ( $_ = $q->fetchrow_hashref())
    {
        $_ -> {'STATE'} = $state_name{$_ -> {'STATE'}};
        if ($link{$_ -> {'FROM'} . "=" . $_ -> {'TO'}})
        {
            push @{$link{$_ -> {'FROM'} . "=" . $_ -> {'TO'}}->{transfer_queue}}, {
                    state => $_ -> {'STATE'},
                    priority => $_ -> {'PRIORITY'},
                    files => $_ -> {'FILES'},
                    bytes => $_ -> {'BYTES'},
                    time_update => $_ -> {'TIME_UPDATE'}
            };
        }
        else
        {
            $link{$_ -> {'FROM'} . "=" . $_ -> {'TO'}} = {
                from => $_ -> {'FROM'},
                to => $_ -> {'TO'},
                from_id => $_ -> {'FROM_ID'},
                to_id => $_ -> {'TO_ID'},
                transfer_queue => [{
                    state => $_ -> {'STATE'},
                    priority => $_ -> {'PRIORITY'},
                    files => $_ -> {'FILES'},
                    bytes => $_ -> {'BYTES'},
                    time_update => $_ -> {'TIME_UPDATE'}
                }]
            };
        }
    }

    while (my ($key, $value) = each(%link))
    {
        push @r, $value;
    }

    return \@r;
}

sub getTransferHistory
{
    my ($core, %h) = @_;
    my $sql = qq {
    select
        :timebin as timebin,
        :timewidth as timewidth,
        n1.name as from_node,
        n2.name as to_node,
        nvl(sum(done_files), 0) as done_files,
        nvl(sum(done_bytes), 0) as done_bytes,
        nvl(sum(fail_files), 0) as fail_files,
        nvl(sum(fail_bytes), 0) as fail_bytes,
        nvl(sum(expire_files), 0) as expire_files,
        nvl(sum(expire_bytes), 0) as expire_bytes,
        cast((nvl(sum(done_bytes), 0) / :timewidth) as number(20, 2)) as rate
    from
        t_history_link_events,
        t_adm_node n1,
        t_adm_node n2
    where
        from_node = n1.id and
        to_node = n2.id };

    my $where_stmt = "";
    my %param;
    my @r;

    $param{':timebin'} = $h{timebin};
    $param{':timewidth'} = $h{timewidth};

    if ($h{from_node})
    {
        $where_stmt .= qq { and\n            n1.name = :from_node};
        $param{':from_node'} = $h{from_node};
    }

    if ($h{to_node})
    {
        $where_stmt .= qq { and\n            n2.name = :to_node};
        $param{':to_Node'} = $h{to_node};
    }

    if ($h{timebin})
    {
        $where_stmt .= qq { and\n            timebin <= :timebin};
        $param{':timebin'} = PHEDEX::Core::Util::str2time($h{timebin});

        if ($h{timewidth})
        {
            $where_stmt .= qq { and\n            timebin > :after};
            $param{':after'} = $param{':timebin'} - $h{timewidth};
        }
    }

    # now take care of the where clause

    if ($where_stmt)
    {
        $sql .= $where_stmt;
    }
    else
    {
        # limit the number of record to 1000
        $sql .= qq { and\n            rownum <= 1000};
    }

    $sql .= qq {\ngroup by n1.name, n2.name };

    # now execute the query
    my $q = PHEDEX::Core::SQL::execute_sql( $core, $sql, %param );
    while ( $_ = $q->fetchrow_hashref() )
    {
        # format the time stamp
        if ($_->{'TIMEBIN'})
        {
            $_->{'TIMEBIN'} = strftime("%Y-%m-%d %H:%M:%S", gmtime( $_->{'TIMEBIN'}));
        }
        push @r, $_;
    }

    # return $sql, %param;
    return \@r;
}

1;
