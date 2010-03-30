package App::Git::Sync;
use Moose;
use Moose::Autobox;
use Net::GitHub::V2::Repositories;
use Data::Dumper;
use FindBin qw/$Bin/;
use MooseX::Types::Moose qw/ ArrayRef HashRef Str Bool /;
use MooseX::Types::Path::Class;
use Config::INI::Reader;
use List::MoreUtils qw/ any /;
use Carp qw/ cluck confess /;
use namespace::autoclean;

our $VERSION = '0.001';

# Yes, this is flagrantly a script, even though it's a class.
# No OO to be found here, sue me.

with 'MooseX::Getopt';

has verbose => ( is => 'ro', isa => Bool, default => 0 );

foreach my $name (qw/ user token /) {
    has "github_$name" => (
        isa => Str,
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

has _github_repositories => (
    isa => 'Net::GitHub::V2::Repositories',
    lazy_build => 1,
    is => 'bare',
    handles => {
        github_list_user_repositories => 'list',
        github_show_user_repository => 'show',
     },
    traits => [qw/ NoGetopt /],
);

my $get_net_github_repos = sub {
    my $self = shift;
    Net::GitHub::V2::Repositories->new(
        login => $self->github_user, token => $self->github_token,
        repo => (shift || 'RequiredButCanBeAnything'),
        owner => $self->github_user,
    );
};

sub _build__github_repositories {
    my $self = shift;
    $self->$get_net_github_repos();
}

sub get_github_network {
    my ($self, $name) = @_;

    my $repos = $self->$get_net_github_repos($name);
    my @forks;
    foreach my $member ($repos->network->flatten) {
        if (!ref($member)) {
            warn("Got non ref member '$member' for $name");
            next;
        }
        next if $member->{owner} eq $self->github_user;
        push(@forks, $member);
    }
    return \@forks;
}

has github_urls_to_repos => (
    isa => HashRef[Str],
    lazy_build => 1,
    is => 'ro',
    traits => [qw/NoGetopt /],
);

my $munge_to_auth = sub { local $_ = shift;
    s/http:\/\/github\.com\/\/?([\w-]+)\/(.+)$/git\@github.com:$1\/$2.git/
        ? $_
        : do { cluck("Could not munge_to_auth: $_"); undef; };
};

my $munge_to_anon = sub { local $_ = shift;
    s/http:\/\/github\.com\/\/?([\w-]+)\/(.+)$/git:\/\/github.com\/$1\/$2.git/
        ? $_
        : do { cluck("Could not munge_to_anon: $_"); undef };
};

my $uri_to_repos = sub { local $_ = shift;
    s/^.+\/// or die; $_;
};

sub _build_github_urls_to_repos {
    my $self = shift;
    my @list = $self->github_list_user_repositories->flatten;
    die($list[1]) if $list[0] =~ /error/;
    return {
        map { $_->$munge_to_auth() => $_->$uri_to_repos }
        map { $_->{url} }
        @list
    };
}

has gitdir => (
    is => 'ro',
    isa => 'Path::Class::Dir',
    required => 1,
    coerce   => 1,
    lazy_build => 1,
);

sub _build_gitdir  {
    my $val = `git config --global sync.dir`;
    chomp($val);
    die("Sync dir not set in git, say: git config --global sync.dir /home/me/code/git or pass a --gitdir parameter\n")
            unless $val;
}

has checkouts => (
    is => 'ro',
    isa => ArrayRef['Path::Class::Dir'],
    lazy_build => 1,
    traits => [qw/ NoGetopt /],
);

sub _build_checkouts {
    my $self = shift;
    [ grep { $_->isa('Path::Class::Dir') } $self->gitdir->children ];
}

has checkout_inifiles => (
    is => 'ro',
    isa => HashRef,
    lazy_build => 1,
    traits => [qw/ NoGetopt /],
);

sub _build_checkout_inifiles {
    my $self = shift;
    return {
        map { $_->[0] => Config::INI::Reader->read_file($_->[1]) }
        map { [ $_, "$_/.git/config" ] } # FIXME
        grep { -r "$_/.git/config" ? 1 : do { warn("$_ does not appear to be a git repository"); 0 } }
        @{ $self->checkouts }
    }
}

has checkout_remotes => (
    is => 'ro',
    isa => HashRef,
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
    isa => ArrayRef[Str],
    is => 'ro',
    lazy_build => 1,
);

sub _build_remotes_list {
    my $self = shift;
    [ map { values %$_ } values %{$self->checkout_remotes} ];
}

sub run {
    my $self = shift;
    my $github_repos = { %{ $self->github_urls_to_repos } };
    foreach my $remote (@{ $self->remotes_list }) {
        delete $github_repos->{$remote};
    }
    chdir $self->gitdir or die $!;
    foreach my $remote (keys %{ $github_repos }) {
        warn("Cloning " . $github_repos->{$remote} . " ($remote)\n");
        system("git clone $remote") and warn $!;
    }
    CHECKOUT: foreach my $checkout (keys %{ $self->checkout_remotes }) {
        my $remotes = $self->checkout_remotes->{$checkout};
        chdir($checkout) or die("$! for $checkout");
        foreach my $remote (keys %{ $remotes }) {
            next CHECKOUT if $github_repos->{$remote};
            warn("Fetching $remote into $checkout\n");
            # FIXME - Deal with deleted repos by capturing output and parsing..
            system("git fetch $remote") and warn $!;
        }

        my $origin = $remotes->{origin} || warn("No origin remote " . Dumper($remotes));
        next unless $origin;
        my $repos_name = $self->github_urls_to_repos->{$origin};
        unless ($repos_name) {
            warn("No repos name");
            next;
        }
        my @remote_uris = values %{ $remotes };
        foreach my $network_member ($self->get_github_network($repos_name)->flatten) {
            my $remote_name = $network_member->{owner};
            my ($anon_uri, $auth_uri) = map { $_->($network_member->{url}) } ($munge_to_anon, $munge_to_auth);
            next unless $anon_uri;
            next if any { $_ eq $anon_uri or $_ eq $auth_uri } @remote_uris;
            warn("Added remote for $remote_name\n");
            system("git remote add $remote_name $anon_uri")
                and die $!;
            system("git fetch $remote_name")
                and die $!;
        }
    }
}

__PACKAGE__->meta->make_immutable;

=head1 NAME

App::Git::Sync

=head1 SYNOPSIS

    git config --global github.user <youruser>
    git config --global github.token <yourtoken from github.com/account>
    git-sync --gitdir /home/t0m/code/git

=head1 DESCRIPTION

C<git-sync> is a simple script to keep all of your checkouts up to date.

It will work through every repository which you have in your git dir,
and if that repository exists on github, then its network will be looked up,
any remotes which you haven't got added will be added, and all your remotes
will be fetched.

Any repositories which you have on github that are not checked out locally
will be cloned (and then remotes will be added and fetched).

=head1 TODO

=over

=item Use git config to store git dir

=item Factor out github code, so that you can have multiple git services to clone all of (e.g. Catgit / Moose git)

=item Ability to automatically mirror out into alternate repositories

=item Generally make it suck less than a quick hack I wrote on the train.

=back

=head1 AUTHOR

Tomas Doran (t0m) C<< <bobtfish@bobtfish.net >>

=head1 LICENSE

Copyright 2009 Tomas Doran, some rights reserved.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

