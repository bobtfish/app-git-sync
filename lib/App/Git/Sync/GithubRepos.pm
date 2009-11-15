package App::Git::Sync::GithubRepos;
# ABSTRACT: Represents a github repository, which may, or may not exist on disk.
use Moose;
use namespace::autoclean;

with 'App::Git::Sync::SetOfRemotes';

sub _build_remotes {
    Carp::confess(shift() . " should only be constructed by App::Git::Sync::ProjectGatherer::Github, not " . caller);
}

__PACKAGE__->meta->make_immutable;
