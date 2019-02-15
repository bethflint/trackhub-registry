=head1 LICENSE

Copyright [2015-2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Catalyst::Model::ElasticSearch;

use Moose;
use namespace::autoclean;
use Search::Elasticsearch;
use Registry::Utils::File qw/slurp_file/;
use Registry;
use Carp;
use JSON;
extends 'Catalyst::Model';


# ABSTRACT: A simple Catalyst model to interface with Search::Elasticsearch
# Adapted from Catalyst::Model::Search::ElasticSearch
=head1 SYNOPSIS

    package My::App;
    use strict;
    use warnings;

    use Catalyst;

    our $VERSION = '0.01';
    __PACKAGE__->config(
      name            => 'Test::App',
      'Model::Search' => {
        nodes           => 'localhost:9200',
        request_timeout => 30,
        max_requests    => 10_000
      }
    );

    __PACKAGE__->setup;


    package My::App::Model::Search;
    use Moose;
    use namespace::autoclean;
    extends 'Catalyst::Model::Search::ElasticSearch';

    __PACKAGE__->meta->make_immutable;
    1;

    package My::App::Controller::Root;
    use base 'Catalyst::Controller';
    __PACKAGE__->config(namespace => '');

    sub search : Local {
      my ($self, $c) = @_;
      my $params = $c->req->params;
      my $search = $c->model('Search');
      my $results = $search->search(
        index => 'test',
        type  => 'test',
        body  => { query => { term => { schpongle => $params->{'q'} } } }
      );
      $c->stash( results => $results );

    }

=head1 CONFIGURATION PARAMETERS AND ATTRIBUTES

=head2 nodes

A list of nodes to connect to.

=cut

has 'nodes' => (
  is      => 'rw',
  lazy    => 1,
  default => "localhost:9200",
);

=head2 transport

The transport to use to interact with the Elasticsearch API.  See L<Search::Elasticsearch::Transport|Search::Elasticsearch::Transport> for options.

=cut

has 'transport' => (
  is      => 'rw',
  lazy    => 1,
  default => "+Search::Elasticsearch::Transport",
);

=head2 _additional_opts

Stores other key/value pairs to pass to L<Search::Elasticsearch|Search::Elasticsearch>.

=cut

has '_additional_opts' => (
  is      => 'rw',
  lazy    => 1,
  isa     => 'HashRef',
  default => sub { { send_get_body_as => 'POST', cxn_pool => 'Static'} },
);

=head2 _es

The L<Search::Elasticsearch> object.

The follwing helper methods have been replaced by the Search::Elasticsearch::Bulk
class. Similarly, scrolled_search() has been replaced by the Search::Elasticsearch::Scroll.
These helper classes are accessible as: 
  $bulk   = $e->bulk_helper( %args_to_new );
  $scroll = $e->scroll_helper( %args_to_new );

==> 
 - remove bulk_(index|create|delete) and reindex
 - add bulk_helper, scroll_helper
 - remove searchqs, scrolled_search (not supported)
 - add indices (returns Search::Elasticsearch::Client::Indices
 - add cluster (returns Search::Elasticsearch::Client::Cluster)
 - other?

Given the method returns a Search::Elasticsearch::Client::Direct it's better
to look at what it now supports.

See https://metacpan.org/pod/Search::Elasticsearch::Client::Direct for a list of methods
grouped according to category

=cut

has '_es' => (
  is       => 'ro',
  lazy     => 1,
  builder  => '_build_es',
  handles  => {
    map { $_ => $_ }
      qw(
      search scrolled_search count index get get_source mget create delete
      bulk bulk_helper scroll_helper indices
      )
  },
);

has schema_location => (
  is => 'ro',
  isa => 'Str',
  required => 1
);


sub _build_es {
  my $self = shift;
  return Search::Elasticsearch->new(
    nodes     => $self->nodes,
    transport => $self->transport,
    %{ $self->_additional_opts },
  );

}

around BUILDARGS => sub {
  my $orig   = shift;
  my $class  = shift;

  my $params = $class->$orig(@_);
  # NOTE: also update this: other stuff deprecated?
  # See https://metacpan.org/pod/Search::Elasticsearch#MIGRATING-FROM-ElasticSearch.pm
  if (defined $params->{servers}) {
    carp "Passing 'servers' is deprecated, use 'nodes' now";
    $params->{nodes} = delete $params->{servers};
  }
  my %additional_opts = %{$params};
  delete $additional_opts{$_} for qw/ nodes transport /;
  $params->{_additional_opts} = \%additional_opts;
  return $params;
};

# Automatically deploy schemas to the configured backend if it is required
around _build_es => sub {
  my $orig = shift;
  my $self = shift;
  
  my $client = $self->$orig(@_);
  foreach my $schema_name (qw/reports trackhub/) {
      
      my $schema_path = File::Spec->catfile(
        $self->schema_location, # Defined in Registry.pm
        $schema_name.'_mappings.json'
      );
      print "Creating index '$schema_name' with mapping $schema_path\n";
      
      # Create indexes and load mappings if they're not present
      unless ($client->indices->exists( index => $schema_name.'_v1' ) ) {
        $client->indices->create(
          index => $schema_name.'_v1', 
          # FIXME, this should reflect actual schema version, but is deeply
          # embedded into deployment
          body => decode_json( slurp_file( $schema_path ) )
        );
        $client->indices->refresh; # If only ES were a proper database
      }
  }
  return $client;
};


=head1 SEE ALSO

=over

=item *

The Catalyst Advent article on integrating Elasticsearch into your app: L<http://www.catalystframework.org/calendar/2010/2>

=item *

L<Search::Elasticsearch|Search::Elasticsearch> - Elasticsearch interface this
model provides access to

=item *

L<http://www.elasticsearch.org/> - Open Source Distributed Real Time Search and Analytics

=back

=cut


__PACKAGE__->meta->make_immutable;
1;
