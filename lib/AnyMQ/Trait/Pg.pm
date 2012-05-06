package AnyMQ::Trait::Pg;

use 5.010;

use Any::Moose 'Role';

use AnyEvent::Pg 0.03;
use JSON;
use Try::Tiny;

has 'dsn' => (
    is => 'ro',
    isa => 'Str',
    default => '',
);

has '_client' => (
    is => 'ro',
    isa => 'AnyEvent::Pg',
    builder => '_build_client',
    predicate => '_client_exists',
);

has 'on_connect' => (
    is => 'ro',
    isa => 'Maybe[CodeRef]',
);

has 'on_error' => (
    is => 'ro',
    isa => 'Maybe[CodeRef]',
);

has 'channels' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub { [] },
    traits => [ 'Array' ],
    handles => {
        'add_channel'  => 'push',
        'all_channels' => 'elements',
    },
);

has 'publish_queue' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub { [] },
    traits => [ 'Array' ],
    handles => {
        'publish_queue_push'    => 'push',
        'publish_queue_unshift' => 'unshift',
    },
);

has 'is_connected' => (
    is => 'rw',
    isa => 'Bool',
);

has '_json' => ( is => 'rw', lazy_build => 1, isa => 'JSON' );

# JSON codec pack
sub _build__json {
    my ($self) = @_;
    return JSON->new->utf8;
}

sub _build_client {
    my ($self) = @_;

    my $pg = AnyEvent::Pg->new(
        $self->dsn,
        on_connect       => sub { $self->_on_connect(@_) },
        on_connect_error => sub { $self->_on_connect_error(@_) },
        on_error         => sub { $self->_on_error(@_) },
        on_notify        => sub { $self->_on_notify(@_) },
    );

    return $pg;
}

sub listen {
    my ($self, $channel) = @_;

    $self->add_channel($channel);
    $self->_client->listen($channel) if $self->is_connected;
}

sub notify {
    my ($self, @rest) = @_;

    if ($self->is_connected) {
        $self->_client->notify(@rest);
    } else {
        $self->publish_queue_push(\@rest);
    }
}

sub encode_event {
    my ($self, $evt) = @_;

    return $evt unless ref $evt;

    # encode refs with JSON
    return $self->_json->encode($evt);
}

sub _on_connect {
    my $self = shift;

    $self->is_connected(1);
    $self->on_connect->(@_) if $self->on_connect;

    if ($self->all_channels) {
        $self->_client->listen($_) for $self->all_channels;
    }

    while (my $evt = $self->publish_queue_unshift) {
        $self->_client->notify(@$evt);
    }
}

sub _on_connect_error {
    my ($self, @rest) = @_;

    $self->is_connected(0);
    $self->_on_error(@rest);
}

sub _on_error {
    my $self = shift;
    my ($pg) = @_;

    my $err = $pg->dbc->errorMessage;

    if ($self->on_error) {
        $self->on_error->(@_);
    } else {
        warn "AnyMQ::Pg error: $err";
    }
}

sub _on_notify {
    my ($self, $pg, $channel, $pid, $payload) = @_;

    my $evt;

    # assume payload is JSON
    try {
        # try decoding from json
        $evt = $self->_json->decode($payload);
    } catch {
        # we'll make the event whatever raw data we got from the payload
        $evt = $payload;
    };

    # no payload at all
    $evt //= { 'name' => $channel };

    # notify listeners
    $self->topic($channel)->append_to_queues($evt);
}

sub new_topic {
    my ($self, $opt) = @_;

    # name of topic to subscribe to, passed in
    $opt = { name => $opt } unless ref $opt;

    # use our topic role
    AnyMQ::Topic->new_with_traits(
        %$opt,
        traits => [ 'Pg' ],
        bus => $self,
    );
}

sub DEMOLISH {}; after 'DEMOLISH' => sub {
    my ($self, $igd) = @_;

    return if $igd;

    $self->_client->destroy if $self->_client_exists;
};

1;
