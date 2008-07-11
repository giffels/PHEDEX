package PHEDEX::Core::Identity;

=head1 NAME

PHEDEX::Core::Identity - SQL for logging and retrieving user actions
to the database


=head1 SYNOPSIS

use PHEDEX::Core::Identity;
my $ident_id = $self->fetchAndSyncIdentity(%ident_params);
my $client_id = $self->logClientInfo(%client_params);

=head1 DESCRIPTION

The PhEDEx database has tables to log user identity and client
software information.  (See t_adm_identity, t_adm_client*).  This
information normally comes from the SecurityModule, which interfaces
with another DB.  The PhEDEx data is written to create relational
relationships between SecurityModule authenticated accesses and user
actions (such as making a request).

=head1 METHODS

=over

=cut

use strict;
use warnings;
use base 'PHEDEX::Core::SQL';

use Carp;

our @EXPORT = qw( );

# Probably will never need parameters for this object, but anyway...
our %params =
	(
	);

sub new
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new(%params,@_);
  bless $self, $class;
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
  return unless $attr =~ /[^A-Z]/;  # skip DESTROY and all-cap methods
  my $parent = "SUPER::" . $attr;
  $self->$parent(@_);
}

=pod

=item fetchAndSyncIdentity($self, %identity_args)

Tries to lookup the user's identity id from the database, based on
%identity_args.  If the unique identifying parameters of
%identity_args are found, but other parameters have changed (e.g.,
name and email) then the identity record is updated and then the
identity id is returned.  If the identity has never been logged to the
databse, then it is logged and the identity id returned.

AUTH_METHOD, NAME, and EMAIL are required arguments.  AUTH_METHOD can
be one of CERTIFICATE for certificate-based authentication and
PASSWORD for password based authentication.

If AUTH_METHOD is CERTIFICATE, then DN and CERTIFICATE parameters must
be passed.

If AUTH_METHOD is PASSWORD, then the USERNAME parameter must be
passed.

=cut

sub fetchAndSyncIdentity
{
    my ($self, %h) = @_;

    foreach my $required (qw (AUTH_METHOD NAME EMAIL) ) {
	unless ($h{$required}) {
	    $self->Error("fetchIdentity required parameter $required was not defined");
	    return undef;
	}
    }

    my @to_sync;
    if ($h{AUTH_METHOD} eq 'CERTIFICATE') {
	unless ($h{DN} && $h{CERTIFICATE}) {
	    $self->Error("fetchIdentity requires DN and CERTIFICATE when AUTH_METHOD is CERTIFICATE");
	    return undef;
	}
	@to_sync = qw(SECMOD_ID NAME EMAIL DN CERTIFICATE);	
    } elsif ($h{AUTH_METHOD} eq 'PASSWORD') {
	unless ($h{USERNAME}) {
	    $self->Error("fetchIdentity requires USERNAME when AUTH_METHOD is PASSWORD");
	    return undef;
	}
	@to_sync = qw(SECMOD_ID NAME EMAIL USERNAME);
    } else { 
	$self->Error("fetchIdentity AUTH_METHOD $h{AUTH_METHOD} is not supported");
	return undef;
    }

    my $id = { map { $_ => $h{$_} } @to_sync };
    my $now = time();

    # Look up a logged identity by either the SecurityModule ID, DN, or username
    my $q = &dbexec($$self{DBH},
		    qq{ select id, secmod_id, name, email, dn, certificate, username
		          from t_adm_identity where secmod_id = :secmod_id
			                         or dn = :dn
				                 or username = :username
			    order by time_update desc },
		    ':secmod_id' => $$id{SECMOD_ID},
		    ':dn' => ($$id{DN} || 'dummy'),
		    ':username' => ($$id{USERNAME} || 'dummy') );

    my $logged_id = $q->fetchrow_hashref();

    my $synced = ($logged_id ? 1 : 0);
    foreach my $param (@to_sync) {
	last if !$synced;
	no warnings;  # we need to compare undef values too
	$synced &&= $$logged_id{$param} eq $$id{$param};
    }

    if ($logged_id && $synced) {
	# If everything is logged and up-to-date, return the identity information
	return $logged_id;
    } elsif ($logged_id && !$synced) {
	# If it is logged, but out of date, update it then return the information by recursing
	my $sql = qq{ update t_adm_identity set };
	my @params = map { "$_ = :$_" } (@to_sync, "TIME_UPDATE");
	$sql .= join(', ', @params);
	$sql .= qq{ where id = :id };
	my %binds = map { (":$_" => $$id{$_}) } @to_sync;
	$binds{':TIME_UPDATE'} = $now;
	$binds{':ID'} = $$logged_id{ID};

	&dbexec($$self{DBH}, $sql, %binds);
	return $self->fetchIdentity(%h);
    } else {
	# If it is not logged, log it then return it by recursing
	my $sql = qq{ insert into t_adm_identity };
	$sql .= '('.join(', ', "ID", @to_sync, "TIME_UPDATE").') ';
	$sql .= 'values ('.join(', ', "seq_adm_identity.nextval", map { ":$_" } (@to_sync,'TIME_UPDATE')).')';
	my %binds = map { (":$_" => $$id{$_}) } @to_sync;
	$binds{':TIME_UPDATE'} = $now;

	&dbexec($$self{DBH}, $sql, %binds);
	return $self->fetchIdentity(%h);
    }
}

=pod

=item makeObjWithAttrs($self, $kind, $link, $obj, %attr)

Poor man's obj->relational mapper to tables of the form 't_${kind}'
with a child table 't_${kind}_attr', the latter which stores arbitrary
name-value pairs as strings.

$kind is the object name, usually a table name without the 't_'
prefix.

$link is the name of a column which contains a reference to the parent
table of the object

$obj is a hashref to the object fields, with named parameters

%attr is a hash of parameters to store for the object.

=cut

sub makeObjWithAttrs
{
  my ($self, $kind, $link, $obj, @attrs) = @_;
  my ($tname, $sname) = ("t_$kind", "seq_$kind");
  my @objfields = keys %$obj;
  my %objattrs = map { (":attr_$_" => $$obj{$_}) } @objfields;

  my $objsql =
    "insert into $tname ("
    . join(", ", "id", @objfields)
    . ")\n values ("
    . join(", ", "$sname.nextval", map { ":attr_$_" } @objfields)
    . ")\n returning id into :id";
  my $id = undef;
  &dbexec($self->{DBH}, $objsql, ":id" => \$id, %objattrs);

  $tname .= "_attr"; $sname .= "_attr";
  while (@attrs)
  {
    my ($name, $value) = splice(@attrs, 0, 2);
    &dbexec($self->{DBH}, qq{
      insert into $tname (id, $link, name, value)
      values ($sname.nextval, :Id, :name, :value)},
      ":id" => $id, ":name" => $name, ":value" => $value);
  }

  return $id;
}

=pod

=item logClientInfo ($self, %attr)

Logs arbitrary data about a client.

%attr can have any data (ultimately stored as strings), but
REMOTE_HOST and USER_AGENT are required.

Returns the client id for the data stored.

=cut

sub logClientInfo
{
    my ($self, %h) = @_;

    foreach my $required ( qw(IDENTITY REMOTE_HOST USER_AGENT) ) {
	unless ($h{$required}) {
	    $self->Error("logClientInfo required parameter $required was not defined");
	    return undef;
	}
    }
    my $identity = $h{IDENTITY};
    delete $h{IDENTITY};

    my $cid = &makeObjWithAttrs
	($$self{DBH}, "adm_contact", "contact", {}, %h);
    
    my $client = &makeObjWithAttrs
	($$self{DBH}, "adm_client", undef,
	 { "identity" => $identity, "contact" => $cid });
    
    return $client;
}

=pod

=item getClientData ($self, $clientid)

Returns a hash of information about a client given a client id.

=cut

sub getClientData 
{
    my ($self, $clientid) = @_;
    my $contactsql = qq{ select name, value 
                             from t_adm_contact_attr con_attr 
                             join t_adm_contact con on con.id = con_attr.contact
                             join t_adm_client cli on cli.contact = con.id
			     where cli.id = :id order by con_attr.id};
    my $identsql  = qq{ select ident.name, ident.email, ident.dn, ident.certificate
                            from t_adm_identity ident
                            join t_adm_client cli on cli.identity = ident.id
			    where cli.id = :id order by ident.id};
    
    
    my %types = ('CONTACT_ATTR'  => $contactsql, 
		 'IDENTITY' => $identsql);
    
    my $result = {};
    
    while (my ($type, $sql) = each %types) {
	my $q = &dbexec($$self{DBH}, $sql, ':id' => $clientid);
	if ($type eq 'CONTACT_ATTR') {
	    $result->{$type} = {};
	    while (my ($name, $value) = $q->fetchrow_array()) {
		$result->{$type}->{$name} = $value;
	    }
	} elsif ($type eq 'IDENTITY') {
	    $result->{$type} = $q->fetchrow_hashref();
	}
    }
    return $result;
}

=pod

=item dn_to_human_name ($dn)

Attempts to parse a certificate distinguished name and return a normal
human name.

e.g. if given '/DC=org/DC=doegrids/OU=People/CN=Ricky Egeland 693921'
this function returns 'Ricky Egeland'

=cut

sub dn_to_human_name
{
    my $dn = shift @_;
    return undef unless $dn;
    my @names = ($dn =~ m:/CN=([^/]+?)[\s\d]*(/|$):g);
    my $name = $names[0];
    foreach (@names) {
      $name = $_ if length $_ > length $name;
    }
    $name =~ s/\b(\w)/\U$1/g;
    return $name;
}

1;

=pod

=back

=head1 SEE ALSO...

L<PHEDEX::Core::SQL|PHEDEX::Core::SQL>,

=cut
