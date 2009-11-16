package App::Git::Sync;
use Moose;
use Moose::Autobox;
use Net::GitHub::V2::Repositories;
use Data::Dumper;
use FindBin qw/$Bin/;
use MooseX::Types::Moose qw/ ArrayRef HashRef Str Bool /;
use MooseX::Types::Path::Class qw/Dir/;
use aliased 'App::Git::Sync::Repos';
use List::MoreUtils qw/ any /;
use App::Git::Sync::Types qw/ProjectGatherer/;
use namespace::autoclean;

our $VERSION = '0.001';

# Yes, this is flagrantly a script, even though it's a class.
# No OO to be found here, sue me.

with 'MooseX::Getopt';

has verbose => ( is => 'ro', isa => Bool, default => 0 );

has gitdir => (
    is => 'ro',
    isa => Dir,
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

has _repos_dirs => (
    is => 'ro',
    isa => ArrayRef['Path::Class::Dir'],
    lazy => 1,
    builder => '_build_repos_dirs',
);

sub _build_repos_dirs {
    my $self = shift;
    [
        grep { -r $_->file('.git', 'config') }
        grep { $_->isa('Path::Class::Dir') } $self->gitdir->children
    ];
}

has projects => (
    is => 'ro',
    isa => ArrayRef[Repos],
    lazy_build => 1,
    traits => [qw/ NoGetopt /],
);

sub _build_projects {
    my $self = shift;
    return [
        map { Repos->new(gitdir => $self->gitdir, name => $_->relative($self->gitdir)->stringify) } $self->_repos_dirs->flatten
    ];
}

has remotes_list => (
    isa => ArrayRef[Str],
    is => 'ro',
    lazy_build => 1,
);

sub _build_remotes_list {
    my $self = shift;
    [ map { $_->remote_uris } $self->projects->flatten ];
}

use App::Git::Sync::ProjectGatherer::Github;
use App::Git::Sync::ProjectGatherer::LocalDisk;

has _github_gatherer => ( isa => 'App::Git::Sync::ProjectGatherer::Github', is => 'ro',
    default => sub {
        my $self = shift;
        App::Git::Sync::ProjectGatherer::Github->new({ gitdir => $self->gitdir, user => $self->github_user, token => $self->github_token });
    },
    handles => {
        map { 'github_' . $_ => $_ }
        qw/urls_to_repos get_network/
    },
);

has _project_gatherers => ( isa => ArrayRef[ProjectGatherer], is => 'ro', lazy => 1, default => sub {
    my $self = shift;
    [
        $self->_github_gatherer,
        App::Git::Sync::ProjectGatherer::LocalDisk->new({ gitdir => $self->gitdir }),
    ]
} );

sub _gather_possible_projects {
    [ map { $_->gather->flatten } shift->_project_gatherers->flatten ];
}

my $munge_to_auth = sub { local $_ = shift;
    s/http:\/\/github\.com\/([\w-]+)\/(.+)$/git\@github.com:$1\/$2.git/ or die("Could not munge_to_auth: $_"); $_;
};

my $munge_to_anon = sub { local $_ = shift;
    s/http:\/\/github\.com\/([\w-]+)\/(.+)$/git:\/\/github.com\/$1\/$2.git/ or die("Could not munge_to_anon: $_"); $_;
};

# Gather list of projects currently held.
# Gather all the interesting 'projects' from all sources
# For each current project, work out if it wants to consume one (or more) of the interesting projects
# For all interesting projects which are left, clone
# For all the projects, do a fetch on all remotes.

sub run {
    my $self = shift;
    chdir $self->gitdir or die $!;
    
    my $local_projects = $self->projects;
    my $all_possible_projects = $self->_gather_possible_projects;

    my $github_repos = { %{ $self->github_urls_to_repos } };
    foreach my $remote (@{ $self->remotes_list }) {
        delete $github_repos->{$remote};
    }
    foreach my $remote (keys %{ $github_repos }) {
        warn("Cloning " . $github_repos->{$remote} . " ($remote)\n");
        system("git clone $remote") and die $!;
    }
    CHECKOUT: foreach my $repos ($self->projects->flatten) {
        my $remotes = $repos->remotes;
        chdir($repos->directory) or die("$! for " . $repos->name);
        foreach my $remote (keys %{ $remotes }) {
            next CHECKOUT if $github_repos->{$remote};
            warn("Fetching $remote into " . $repos->name . "\n");
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
        foreach my $network_member ($self->github_get_network($repos_name)->flatten) {
            my $remote_name = $network_member->{owner};
            my ($anon_uri, $auth_uri) = map { $_->($network_member->{url}) } ($munge_to_anon, $munge_to_auth);
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

C<git-sync> is a simple script to keep all of your repositories up to date.

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

