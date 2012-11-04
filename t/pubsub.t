#!/usr/bin/env perl

use Test::More tests => 3;
use FindBin;
use lib "$FindBin::Bin/../lib";
use AnyEvent;
use AnyMQ;
use AnyMQ::Pg;
use Data::Dumper;

my $cv;
my $listener;
my $notif_count = 0;

BEGIN {
    use_ok('AnyMQ::Pg') || warn "Error using AnyMQ::Pg!\n";
}

SKIP: {
    skip "Set \$AMQPG_TESTS to test with AnyMQ::Pg", 2
        unless $ENV{AMQPG_TESTS};

    run_tests();
}

sub run_tests {
    my $bus = AnyMQ->new_with_traits(
        traits     => ['Pg'],
        dsn        => 'user=postgres dbname=postgres',
        on_connect       => \&connected,
        on_error         => \&error,
        on_connect_error => \&connect_error,
    );
    $cv = AE::cv;

    my $topic = $bus->topic('LOLHI');
    $topic->publish({ blah => 123 });

    $cv->recv;
}

sub got_notification {
    my ($notif) = @_;
    $notif_count++;
    is($notif->{blah}, 123, "Got published notification");
    $cv->send if $notif_count == 2;
}

sub connected {
    my ($self) = @_;
    
    my $topic = $self->topic('LOLHI');
    $listener = $self->new_listener($topic);
    $listener->poll(\&got_notification);
    $topic->publish({ blah => 123 });
}

sub error {
    my ($self, $err) = @_;
    warn "Pg error: $err";
    $cv->send;
}

sub connect_error {
    my ($self, $err) = @_;
    warn "Connection error: $err";
    $cv->send;
}

