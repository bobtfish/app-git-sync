package App::Git::Sync::ProjectGatherer::Github;
use Moose;
use MooseX::Types::Common::String qw/NonEmptySimpleStr/;
use MooseX::Types::Moose qw/HashRef Str Object/;
use App::Git::Sync::GithubRepos;
use Moose::Autobox;
use Net::Github::V2;
use Net::GitHub::V2::Repositories;
use namespace::autoclean;

with 'App::Git::Sync::ProjectGatherer'; 

foreach my $name (qw/ user token /) {
    has $name => (
        isa => NonEmptySimpleStr,
        lazy_build => 1,
        is => 'ro',
    );
    __PACKAGE__->meta->add_method( "_build_$name" => sub {
        my $val = `git config --global github.$name`;
        chomp($val);
        die("Github config not set in git, say: git config --global github.$name VALUE\n")
            unless $val;
    });
}


has _repositories => (
    isa => Object,
    lazy_build => 1,
    is => 'bare',
    handles => {
        list_user_repositories => 'list',
        show_user_repository => 'show',
     },
);

my $get_net_github_repos = sub {
    my $self = shift;
    $self->_github_client_class->new(
        login => $self->user, token => $self->token,
        repo => (shift || 'RequiredButCanBeAnything'),
        owner => $self->user,
    );
};

has _github_client_class => ( isa => NonEmptySimpleStr, is => 'ro', default => 'Net::GitHub::V2::Repositories' );

sub _build__repositories {
    my $self = shift;
    $self->$get_net_github_repos();
}

sub get_network {
    my ($self, $name) = @_;

    my $repos = $self->$get_net_github_repos($name);
    my @forks;
    foreach my $member ($repos->network->flatten) {
        if (!ref($member)) {
            warn("Got non ref member '$member' for $name");
            next;
        }
        next if $member->{owner} eq $self->user;
        push(@forks, $member);
    }
    return \@forks;
}

has urls_to_repos => (
    isa => HashRef[Str],
    lazy_build => 1,
    is => 'ro',
);

my $munge_to_auth = sub { local $_ = shift;
    s/http:\/\/github\.com\/([\w-]+)\/(.+)$/git\@github.com:$1\/$2.git/ or die("Could not munge_to_auth: $_"); $_;
};

my $munge_to_anon = sub { local $_ = shift;
    s/http:\/\/github\.com\/([\w-]+)\/(.+)$/git:\/\/github.com\/$1\/$2.git/ or die("Could not munge_to_anon: $_"); $_;
};

my $uri_to_repos = sub { local $_ = shift;
    s/^.+\/// or die; $_;
};

sub _build_urls_to_repos {
    my $self = shift;
    my @list = $self->list_user_repositories->flatten;
    die($list[1]) if $list[0] =~ /error/;
    return {
        map { $_->$munge_to_auth() => $_->$uri_to_repos }
        map { $_->{url} }
        @list
    };
}

sub gather {
    my $self = shift;
    my $urls_to_repos = $self->urls_to_repos;
    [ map { App::Git::Sync::GithubRepos->new( name => $urls_to_repos->{$_}, remotes => { origin => $_ })} keys %$urls_to_repos ];

}

__PACKAGE__->meta->make_immutable;