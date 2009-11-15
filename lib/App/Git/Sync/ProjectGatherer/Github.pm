package App::Git::Sync::ProjectGatherer::Github;
use Moose;
use Net::GitHub::V2::Repositories;
use MooseX::Types::Common::String qw/NonEmptySimpleStr/;
use MooseX::Types::Moose qw/HashRef Str/;
use App::Git::Sync::GithubRepos;
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
    isa => 'Net::GitHub::V2::Repositories',
    lazy_build => 1,
    is => 'bare',
    handles => {
        list_user_repositories => 'list',
        show_user_repository => 'show',
     },
);

my $get_net_github_repos = sub {
    my $self = shift;
    Net::GitHub::V2::Repositories->new(
        login => $self->user, token => $self->token,
        repo => (shift || 'RequiredButCanBeAnything'),
        owner => $self->user,
    );
};

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
    return {
        map { $_->$munge_to_auth() => $_->$uri_to_repos }
        map { $_->{url} }
        $self->list_user_repositories->flatten
    };
}

sub gather {
    my $self = shift;
    my $uris_to_repos = $self->uris_to_repos;
    [ map { App::Git::Sync::GithubRepos->new( name => $uris_to_repos->{$_}, remotes => { origin => $_ })} keys %$uris_to_repos ];
    
}

__PACKAGE__->meta->make_immutable;
