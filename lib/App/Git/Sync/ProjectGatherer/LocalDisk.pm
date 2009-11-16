package App::Git::Sync::ProjectGatherer::LocalDisk;
use Moose;
use MooseX::Types::Moose qw/ArrayRef/;
use MooseX::Types::Path::Class qw/Dir/;
use aliased 'App::Git::Sync::Repos';
use Moose::Autobox;
use namespace::autoclean;

with 'App::Git::Sync::ProjectGatherer';

has gitdir => (
    is => 'ro',
    isa => Dir,
    required => 1,
    coerce   => 1,
);

has _repos_dirs => (
    is => 'ro',
    isa => ArrayRef[Dir],
    lazy => 1,
    builder => '_build_repos_dirs',
);

sub _build_repos_dirs {
    my $self = shift;
    [
        grep { -r $_->file('.git', 'config') }
        grep { $_->isa('Path::Class::Dir') }
        $self->gitdir->children
    ];
}

sub BUILD { shift->gitdir }

sub gather {
    my $self = shift;
    [
        map { Repos->new( gitdir => $self->gitdir, name => $_->relative($self->gitdir)->stringify) }
        $self->_repos_dirs->flatten
    ];
}

__PACKAGE__->meta->make_immutable;
