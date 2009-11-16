use strict;
use warnings;

use Test::More;
use Test::Exception;
use Class::MOP::Class;

my $mock_api_meta = Class::MOP::Class->create_anon_class(
    superclasses => [qw/ Moose::Object /]
);
$mock_api_meta->add_method(list => sub {
    [ map { { url => $_ } } qw[
        http://github.com/bobtfish/project1
        http://github.com/bobtfish/project2
        http://github.com/bobtfish/project3    
    ]]
});

use App::Git::Sync::ProjectGatherer::Github;
my $i;
lives_ok {
    $i = App::Git::Sync::ProjectGatherer::Github->new(
        user => 'bobtfish', token => 'MYTOKEN',
        _github_client_class => $mock_api_meta->name,
    );
};
ok $i;

# FIXME - This is the old interface!
my $urls_to_repos = $i->urls_to_repos;
ok $urls_to_repos;
is ref($urls_to_repos), 'HASH';
is_deeply $urls_to_repos,
    {
        'git@github.com:bobtfish/project1.git' => 'project1',
        'git@github.com:bobtfish/project2.git' => 'project2',
        'git@github.com:bobtfish/project3.git' => 'project3',
    };

# New interface
my $repos_list = $i->gather;
ok $repos_list;
is ref($repos_list), 'ARRAY';
ok scalar @$repos_list;
foreach my $repos (@$repos_list) {
    my $name = $repos->name;
    is_deeply $repos->remotes, { origin => 'git@github.com:bobtfish/' . $name . '.git' };
}

done_testing;
