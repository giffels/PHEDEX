#!/usr/bin/env perl

package PHEDEX::Web::Core;

=pod
=head1 NAME

PHEDEX::Web::Core - fetch, format, and return PhEDEx data

=head1 DESCRIPTION

This is the core module of the PhEDEx Data Service, a framework to
serve PhEDEx data in multiple formats for machine consumption.

=head2 URL Format

Calls to the PhEDEx data service should be made using the following URL format:

C<http://host.cern.ch/phedex/datasvc/FORMAT/INSTANCE/CALL?OPTIONS>

 FORMAT    the desired output format (e.g. xml, json, or perl)
 INSTANCE  the PhEDEx database instance from which to fetch the data
           (e.g. prod, debug, dev)
 CALL      the API call to make (see below)
 OPTIONS   the options to the CALL, in standard query string format

=head2 Output

Each response will have the following data in its "top level"
attributes.  With the XML format, these attributes appear in the
top-level "phedex" element.

 request_timestamp  unix timestamp, time of request
 request_date       human-readable time of request
 request_call       name of API call
 instance           PhEDEx DB instance
 call_time          time it took to serve call
 request_url        the full URL of the request

=head2 Errors

Currently all errors are returned in XML format, with a single <error>
element containing a text description of what went wrong.  For example:

C<http://host.cern.ch/phedex/datasvc/xml/prod/foobar>

   <error>
   API call 'foobar' is not defined.  Check the URL
   </error>


=head1 Calls

=cut


use warnings;
use strict;

use PHEDEX::Core::Timing;
use PHEDEX::Core::SQL;
use PHEDEX::Web::SQL;
use PHEDEX::Web::Format;
use HTML::Entities; # for encoding XML

# If you're thinking of these, I've already tried them and decided against.
#use Cache::FileCache;
#use Cache::MemoryCache;
#use XML::XML2JSON;
#use XML::Writer;

our (%params);

%params = ( DBCONFIG => undef,
	    INSTANCE => undef,
	    REQUEST_URL => undef,
	    REQUEST_TIME => undef,
	    DEBUG => 0
	    );

# A map of API calls to data sources
our $call_data = {
    linkTasks       => [ qw( linkTasks ) ],
    blockReplicas   => [ qw( blockReplicas ) ],
    fileReplicas    => [ qw( fileReplicas ) ],
    nodes           => [ qw( nodes ) ],
    tfc             => [ qw( tfc ) ]
};

# Data source parameters
our $data_sources = {
    linkTasks       => { DATASOURCE => \&PHEDEX::Web::SQL::getLinkTasks,
			 DURATION => 10*60 },
    blockReplicas   => { DATASOURCE => \&PHEDEX::Web::SQL::getBlockReplicas,
			 DURATION => 5*60 },
    fileReplicas    => { DATASOURCE => \&PHEDEX::Web::SQL::getFileReplicas,
			 DURATION => 5*60 },
    nodes           => { DATASOURCE => \&PHEDEX::Web::SQL::getNodes,
			 DURATION => 60*60 },
    tfc             => { DATASOURCE => \&PHEDEX::Web::SQL::getTFC,
			 DURATION => 15*60 }
};

sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = ref($proto) ? $class->SUPER::new(@_) : {};
    
    my %args = (@_);
    map {
        $self->{$_} = defined($args{$_}) ? $args{$_} : $params{$_}
    } keys %params; 

    $self->{REQUEST_TIME} ||= &mytimeofday();

    # Set up database connection
    my $t1 = &mytimeofday();
    &PHEDEX::Core::SQL::connectToDatabase($self, 0);
    my $t2 = &mytimeofday();
    warn "db connection time ", sprintf('%.6f s', $t2-$t1), "\n" if $self->{DEBUG};

    $self->{DBH}->{FetchHashKeyName} = 'NAME_lc';

#    $self->{CACHE} = new Cache::FileCache({cache_root => '/tmp/phedex-cache'});
#    $self->{CACHE} = new Cache::MemoryCache;
    
    bless $self, $class;

    # on initialization fill the caches
#    foreach my $call (grep $cacheable{$_} > 0, keys %cacheable) {
#	$self->refreshCache($call);
#    }

    return $self;
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
    my $parent = "SUPER::" . $attr;
    $self->$parent(@_);
}

sub DESTROY
{
}

sub call
{
    my ($self, $call, %args) = @_;
    no strict 'refs';
    if (!$call) {
	$self->error("No API call provided.  Check the URL");
	return;
    } elsif (!exists ${"PHEDEX::Web::Core::"}{$call}) {
	$self->error("API call '$call' is not defined.  Check the URL");
	return;
    } else {
	my $t1 = &mytimeofday();
	my $obj;
	eval {
	    $obj = &{"PHEDEX::Web::Core::$call"}($self, %args, nocache=>1);
	};
	if ($@) {
	    $self->error("Error when making call '$call':  $@");
	    return;
	}
	my $t2 = &mytimeofday();
	warn "api call '$call' complete in ", sprintf('%.6f s', $t2-$t1), "\n" if $self->{DEBUG};

	# wrap the object in a phedexData element
	$obj->{instance} = $self->{INSTANCE};
	$obj->{request_url} = $self->{REQUEST_URL};
	$obj->{request_call} = $call;
	$obj->{request_timestamp} = $self->{REQUEST_TIME};
	$obj->{request_date} = &formatTime($self->{REQUEST_TIME}, 'stamp');
	$obj->{call_time} = sprintf('%.5f', $t2 - $t1);
	$obj = { phedex => $obj };

	$t1 = &mytimeofday();
	if (grep $_ eq $args{format}, qw( xml json perl )) {
	    &PHEDEX::Web::Format::output(*STDOUT, $args{format}, $obj);
	} else {
	    $self->error("return format requested is unknown or undefined");
	}
	$t2 = &mytimeofday();
	warn "api call '$call' delivered in ", sprintf('%.6f s', $t2-$t1), "\n" if $self->{DEBUG};
    }
}

sub error
{
    my $self = shift;
    my $msg = shift || "no message";
    chomp $msg;
    print "<error>\n", encode_entities($msg),"\n</error>";
}


# API Calls 

sub linkTasks
{
    my ($self, %h) = @_;
    
    my $r = $self->getData('linkTasks', %h);
    return { linkTasks => { status => $r } };
}

=pod

=head2 blockReplicas

Return block replicas with the following structure:

  <block>
     <replica/>
     <replica/>
      ...
  </block>
   ...

where <block> represents a block of files and <replica> represents a
copy of that block at some node.

=head3 options

 block          block name, with '*' wildcards, can be multiple
 node           node name, can be multiple
 se             storage element name, can be multiple
 updated_since  unix timestamp, only return replicas updated since this
                time
 create_since   unix timestamp, only return replicas created since this
                time
 complete       y or n, whether or not to require complete or incomplete
                blocks. Default is to return either

=head3 <block> attributes

 name     block name
 id       PhEDEx block id
 files    files in block
 bytes    bytes in block
 is_open  y or n, if block is open

=head3 <replica> attributes

 node         PhEDEx node name
 node_id      PhEDEx node id
 se           storage element name
 files        files at node
 bytes        bytes of block replica at node
 complete     y or n, if complete
 time_create  unix timestamp of creation
 time_update  unix timestamp of last update

=cut

sub blockReplicas
{
    my ($self, %h) = @_;

    my $r = $self->getData('blockReplicas', %h);

    # Format into block->replica heirarchy
    my $blocks = {};
    foreach my $row (@$r) {
	my $id = $row->{block_id};
	
	# <block> element
	if (!exists $blocks->{ $id }) {
	    $blocks->{ $id } = { id => $id,
				 name => $row->{block_name},
				 files => $row->{block_files},
				 bytes => $row->{block_bytes},
				 is_open => $row->{is_open},
				 replica => []
				 };
	}
	
	# <replica> element
	push @{ $blocks->{ $id }->{replica} }, { node_id => $row->{node_id},
						 node => $row->{node_name},
						 se => $row->{se_name},
						 files => $row->{replica_files},
						 bytes => $row->{replica_bytes},
						 time_create => $row->{replica_create},
						 time_update => $row->{replica_update},
						 complete => $row->{replica_complete}
					     };
    }

    return { block => [values %$blocks] };
}

=pod

=head2 fileReplicas

Return file replicas with the following structure:

  <block>
     <file>
       <replica/>
       <replica/>
       ...
     </file>
     ...
  </block>
   ...

where <block> represents a block of files, <file> represents a file
and <replica> represents a copy of that file at some node.

=head3 options

 block          block name, with '*' wildcards, can be multiple.  required.
 node           node name, can be multiple
 se             storage element name, can be multiple
 updated_since  unix timestamp, only return replicas updated since this
                time
 create_since   unix timestamp, only return replicas created since this
                time
 complete       y or n, whether or not to require complete or incomplete
                blocks. Default is to return either

=head3 <block> attributes

 name     block name
 id       PhEDEx block id
 files    files in block
 bytes    bytes in block
 is_open  y or n, if block is open

=head3 <file> attributes

 name         logical file name
 id           PhEDEx file id
 bytes        bytes in the file
 checksum     checksum of the file
 origin_node  node name of the place of origin for this file
 time_create  time that this file was born in PhEDEx

=head3 <replica> attributes
 node         PhEDEx node name
 node_id      PhEDEx node id
 se           storage element name
 time_create  unix timestamp

=cut

sub fileReplicas
{
    my ($self, %h) = @_;

    &checkRequired(\%h, 'block');

    my $r = $self->getData('fileReplicas', %h);

    my $blocks = {};
    my $files = {};
    my $replicas = {};
    foreach my $row (@$r) {
	my $block_id = $row->{block_id};
	my $node_id = $row->{node_id};
	my $file_id = $row->{file_id};

	# <block> element
	if (!exists $blocks->{ $block_id }) {
	    $blocks->{ $block_id } = { id => $block_id,
				       name => $row->{block_name},
				       files => $row->{block_files},
				       bytes => $row->{block_bytes},
				       is_open => $row->{is_open},
				       file => []
				   };
	}

	# <file> element
	if (!exists $files->{ $file_id }) {
	    $files->{ $file_id } = { id => $row->{file_id},
				     name => $row->{logical_name},
				     bytes => $row->{filesize},
				     checksum => $row->{checksum},
				     time_create => $row->{time_create},
				     origin_node => $row->{origin_node},
				     replica => []
				 };
	    push @{ $blocks->{ $block_id }->{file} }, $files->{ $file_id };
	}
	
	# <replica> element
	push @{ $files->{ $file_id }->{replica} }, { node_id => $row->{node_id},
						     node => $row->{node_name},
						     se => $row->{se_name},
						     time_create => $row->{replica_create}
						 };
    }
    
    return { block => [values %$blocks] };
}

=pod

=head2 nodes

A simple dump of PhEDEx nodes.

=head3 options

 node     PhEDex node name
 noempty  filter out nodes which do not host any data

=head3 <node> attributes

 name        PhEDEx node name
 se          storage element
 kind        node type, e.g. 'Disk' or 'MSS'
 technology  node technology, e.g. 'Castor'
 id          node id

=cut

sub nodes
{
    my ($self, %h) = @_;
    my $r = $self->getData('nodes', %h);
    return { node => $r };
}

=pod

=head2 tfc

Show the TFC published to TMDB for a given node

=head3 options

  node  PhEDEx node name. Required

=head3 <lfn-to-pfn> or <pfn-to-lfn> attributes

See TFC documentation.

=cut

sub tfc
{
    my ($self, %h) = @_;
    &checkRequired(\%h, 'node');
    my $r = $self->getData('tfc', %h);
    return { 'storage-mapping' => { array => $r }  };
}

# Cache controls

sub refreshCache
{
    my ($self, $call) = @_;
    
    foreach my $name (@{ $call_data->{$call} }) {
	my $datasource = $data_sources->{$name}->{DATASOURCE};
	my $duration   = $data_sources->{$name}->{DURATION};
	my $data = &{$datasource}($self);
	$self->{CACHE}->set( $name, $data, $duration.' s' );
    }
}

sub getData
{
    my ($self, $name, %h) = @_;

    my $datasource = $data_sources->{$name}->{DATASOURCE};
    my $duration   = $data_sources->{$name}->{DURATION};

    my $t1 = &mytimeofday();

    my $from_cache;
    my $data;
    $data = $self->{CACHE}->get( $name ) unless $h{nocache};
    if (!defined $data) {
	$data = &{$datasource}($self, %h);
	$self->{CACHE}->set( $name, $data, $duration.' s') unless $h{nocache};
	$from_cache = 0;
    } else {
	$from_cache = 1;
    }

    my $t2 = &mytimeofday();

    warn "got '$name' from ",
    ($from_cache ? 'cache' : 'DB'),
    " in ", sprintf('%.6f s', $t2-$t1), "\n" if $self->{DEBUG};

    return wantarray ? ($data, $from_cache) : $data;
}


# Returns the cache duration for a API call.  If there are multiple
# data sources in an API call then the one with the lowest duration is
# returned
sub getCacheDuration
{
    my ($self, $call) = @_;
    my $min;
    foreach my $name (@{ $call_data->{$call} }) {
	my $duration   = $data_sources->{$name}->{DURATION};
	$min ||= $duration;
	$min = $duration if $duration < $min;
    }
    return $min;
}


# just dies if the required args are not provided or if they are unbounded
sub checkRequired
{
    my ($provided, @required) = @_;
    foreach my $arg (@required) {
	if (!exists $provided->{$arg} ||
	    !defined $provided->{$arg} ||
	    $provided->{$arg} eq '' ||
	    $provided->{$arg} =~ /^\*+$/
	    ) {
	    die "Argument '$arg' is required\n";
	}
    }
}

1;
