package App::Git::Sync;
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

has _github_repositories => (
    isa => 'Net::GitHub::V2::Repositories',
    lazy_build => 1,
    is => 'bare',
    handles => { github_list_user_repositories => 'list' },
    traits => [qw/ NoGetopt /],
);

sub _build__github_repositories {
    my $self = shift;
    Net::GitHub::V2::Repositories->new(
        login => $self->github_user, token => $self->github_token,
        repo => 'Ugh',
        owner => $self->github_user,
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
    return { map { my $url = $_ = $_->{url}; s/^.+\///; $url =~ s/http:\/\/github\.com\/(\w+)\/(.+)$/git\@github.com:$1\/$2.git/ or die; $url => $_; } @{ $self->github_list_user_repositories } };
}

has gitdir => (
    is => 'ro',
    isa => 'Path::Class::Dir',
    required => 1,
    coerce   => 1,
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
        grep { -r "$_/.git/config" ? 1 : do { warn("$_ does not appear to be a git repository"); 0 } }
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

=head1 NAME

App::Git::Sync

=head1 SYNOPSIS

    git config --global github.user <youruser>
    git config --global github.token <yourtoken from github.com/account>
    git-sync --gitdir /home/t0m/code/git

=head1 DESCRIPTION

C<git-sync> is a simple script to keep all of your checkouts up to date.

When run, it will clone any new github repositories (which are not cloned
somewhere within C<--gitdir>, and then will fetch all remotes in all cloned
repositories (except repositories which were just cloned for the first time.

=head1 TODO

=over

=item Use git config to store git dir

=item Factor out github code, so that you can have multiple git services to clone all of (e.g. Catgit / Moose git)

=item Explore github network, so you automatically clone forks

=item Ability to automatically mirror out into alternate repositories

=item Generally make it suck less than a quick hack I wrote on the train.

=back

=head1 AUTHOR

Tomas Doran (t0m) C<< <bobtfish@bobtfish.net >>

=head1 LICENSE

Copyright 2009 Tomas Doran, some rights reserved.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

