package AnyMQ::Topic::Trait::Pg;

use Any::Moose 'Role';

# publish to a channel
after 'publish' => sub {
    my ($self, @events) = @_;

    my $channel = $self->name;

    foreach my $event (@events) {
        my $encoded = $self->bus->encode_event($event) or next;
        $self->bus->notify($channel, $encoded);
    }
};

# subscribe to a channel
after 'add_subscriber' => sub {
    my ($self, $queue) = @_;

    my $channel = $self->name;
    $self->bus->listen($channel);
};

1;
