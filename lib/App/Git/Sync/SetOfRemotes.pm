package App::Git::Sync::SetOfRemotes;
# ABSTRACT: Represents a logical set of remotes.
use Moose::Role;
use MooseX::Types::Moose qw/HashRef/;
use MooseX::Types::Common::String qw/NonEmptySimpleStr/;
use namespace::clean;

requires '_build_remotes';

has name => ( isa => NonEmptySimpleStr, is => 'ro', required => 1 );

has remotes => (
    is => 'ro',
    isa => HashRef[NonEmptySimpleStr],
    builder => '_build_remotes',
    lazy => 1,
    traits => ['Hash'],
    handles => {
        remote_uris => 'values',
    },
);

sub BUILD {}

after BUILD => sub { shift->remotes };

1;
