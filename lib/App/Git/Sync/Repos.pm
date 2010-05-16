package App::Git::Sync::Repos;
# ABSTRACT: Represents an on-disk git repository and its remotes
use Moose;
use MooseX::Types::Common::String qw/NonEmptySimpleStr/;
use MooseX::Types::Path::Class qw/Dir/;
use MooseX::Types::Moose qw/HashRef/;
use Config::INI::Reader;
use namespace::autoclean;

with 'App::Git::Sync::SetOfRemotes';

has _gitdir => ( isa => Dir, is => 'ro', required => 1, init_arg => 'gitdir', coerce => 1 );

sub directory {
    my $self = shift;
    $self->_gitdir->subdir($self->name);
}

has _inifile => (
    is => 'ro',
    isa => HashRef,
    builder => '_build_inifile',
    lazy => 1,
);

sub _build_inifile {
    my $self = shift;
    my $fn = $self->_gitdir->file($self->name, '.git', 'config');
    die("Not a git repository - cannot find $fn") unless -r $fn;
    Config::INI::Reader->read_file($fn);
}

sub BUILD { shift->_inifile }

sub _build_remotes {
    my $self = shift;

    my @remote_keys =
            map { /"(.+)"/ or die; $1 }
            grep { /^remote/ }
            keys %{ $self->_inifile };
    my $out = {};
    foreach my $key (@remote_keys) {
        $out->{$key} = $self->_inifile->{"remote \"$key\""}->{url};
    }
    return $out;
}

__PACKAGE__->meta->make_immutable;