package App::GitHubSync;
use Moose;
use Net::GitHub::V2::Repositories;
use Data::Dumper;
use FindBin qw/$Bin/;
use MooseX::Types::Path::Class;
use Config::INI::Reader;
use namespace::autoclean;

with 'MooseX::Getopt';

foreach my $name (qw/ user token /) {
    has "github_$name" => (
        isa => 'Str',
        lazy_build => 1,
        is => 'ro',
    );
    __PACKAGE__->meta->add_method( "_build_github_$name" => sub {
        my $val = `git config --global github.$name`;
        chomp($val);
        die("Github config not set in git, say: git config --global github.$name VALUE\n")
            unless $val;
    });
}

has github => (
    isa => 'Net::GitHub::V2::Repositories',
    lazy_build => 1,
    is => 'ro',
    traits => [qw/ NoGetopt /],
);

sub _build_github {
    my $self = shift;
    Net::GitHub::V2::Repositories->new(
        login => $self->github_user, token => $self->github_token,
        repo => 'Complete_Lies_-_Faylands_API_Is_Shit',
        owner => 'Your_Mom_On_Stilts',
    );
}

has github_urls_to_repos => (
    isa => 'HashRef[Str]',
    lazy_build => 1,
    is => 'ro',
    traits => [qw/NoGetopt /],
);

sub _build_github_urls_to_repos {
    my $self = shift;
    #http://github.com/bobtfish/namespace-clean
    #git@github.com:bobtfish/acme-UNIVERSAL-cannot.git
    return { map { my $url = $_ = $_->{url}; s/^.+\///; $url =~ s/http:\/\/github\.com\/(\w+)\/(.+)$/git\@github.com:$1\/$2.git/ or die; $url => $_; } @{ $self->github->list } };
}

has gitdir => (
    is => 'ro',
    isa => 'Path::Class::Dir',
    required => 1,
    coerce   => 1,
    default => "/home/t0m/code/git",
);

has checkouts => (
    is => 'ro',
    isa => 'ArrayRef[Path::Class::Dir]',
    lazy_build => 1,
    traits => [qw/ NoGetopt /],
);

sub _build_checkouts {
    my $self = shift;
    [ grep { $_->isa('Path::Class::Dir') } $self->gitdir->children ];
}

has checkout_inifiles => (
    is => 'ro',
    isa => 'HashRef',
    lazy_build => 1,
    traits => [qw/ NoGetopt /],
);

sub _build_checkout_inifiles {
    my $self = shift;
    return {
        map { $_->[0] => Config::INI::Reader->read_file($_->[1]) }
        map { [ $_, "$_/.git/config" ] } # FIXME
        @{ $self->checkouts }
    }
}

has checkout_remotes => (
    is => 'ro',
    isa => 'HashRef',
    lazy_build => 1,
    traits => [qw/ NoGetopt /],
);

sub _build_checkout_remotes {
    my $self = shift;
    my $out = {};
    foreach my $checkout (keys %{$self->checkout_inifiles}) {
        $out->{$checkout} ||= {};
        my @remote_keys =
            map { /"(.+)"/ or die; $1 }
            grep { /^remote/ }
            keys %{ $self->checkout_inifiles->{$checkout} };
        foreach my $key (@remote_keys) {
            $out->{$checkout}->{$key}
                = $self->checkout_inifiles->{$checkout}->{"remote \"$key\""}->{url};
        }
    }
    return $out;
}

has remotes_list => (
    isa => 'ArrayRef[Str]',
    is => 'ro',
    lazy_build => 1,
);

sub _build_remotes_list {
    my $self = shift;
    [ map { values %$_ } values %{$self->checkout_remotes} ];
}

sub run {
    my $self = shift;
    my $github_repos = $self->github_urls_to_repos;
    foreach my $remote (@{ $self->remotes_list }) {
        delete $github_repos->{$remote};
    }
    chdir $self->gitdir or die $!;
    foreach my $remote (keys %{ $github_repos }) {
        warn("Cloning " . $github_repos->{$remote} . " ($remote)\n");
        system("git clone $remote") and die $!;
    }
    CHECKOUT: foreach my $checkout (keys %{ $self->checkout_remotes }) {
        my $remotes = $self->checkout_remotes->{$checkout};
        chdir($checkout) or die("$! for $checkout");
        foreach my $remote (keys %{ $remotes }) {
            next CHECKOUT if $github_repos->{$remote};
            warn("Fetching $remote into $checkout\n");
            system("git fetch $remote") and die $!;
        }
    }
}

__PACKAGE__->meta->make_immutable;

