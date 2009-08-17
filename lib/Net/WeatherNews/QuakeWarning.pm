package Net::WeatherNews::QuakeWarning;

use strict;
use 5.008_001;
our $VERSION = '0.01';

use AnyEvent;
use AnyEvent::HTTP;
use AnyEvent::Socket;
use Any::Moose;
use Digest::MD5 qw(md5_hex);
use DateTime;
use HTTP::Response;
use HTTP::Request;

has email => (
    is => 'rw', isa => 'Str', required => 1
);

has password => (
    is => 'rw', isa => 'Str', required => 1
);

has on_warning => (
    is => 'rw', isa => 'CodeRef',
);

has on_error => (
    is => 'rw', isa => 'CodeRef',
    default => sub { sub { die @_ } },
);

sub connect {
    my $self = shift;

    http_get 'http://lst10s-sp.wni.co.jp/server_list.txt', sub {
        my($body, $hdr) = @_;
        my @servers = split /[\r\n]+/, $body;
        my($ip, $port) = split /:/, $servers[int(rand($#servers+1))];
        $self->connect_stream($ip, $port);
    };
}

sub connect_stream {
    my($self, $ip, $port) = @_;

    tcp_connect $ip, $port, sub {
        my $fh = shift;

        my $handle; $handle = AnyEvent::Handle->new(
            fh => $fh,
            on_eof => sub {
                $handle->destroy;
            },
        );

        my $req = HTTP::Headers->new(
            'User-Agent'                  => "FastCaster/1.0 powered by weathernews.",
            'Accept'                      => '*/*',
            'Cache-Control'               => 'no-cache',
            'X-WNI-Account'               => $self->email,
            'X-WNI-Password'              => md5_hex($self->password),
            'X-WNI-Application-Version'   => "2.2.4.0",
            'X-WNI-Authentication-Method' => 'MDB_MWS',
            'X-WNI-ID'                    => 'Login',
            'X-WNI-Protocol-Version'      => '2.1',
            'X-WNI-TerminalID'            => '211363088',
            'X-WNI-Time'                  => DateTime->now->strftime('%Y/%m/%d %H:%M:%S.%6N'),
        );

        $handle->push_write("GET /login HTTP/1.0\n");
        $handle->push_write($req->as_string);
        $handle->push_write("\n");

        $handle->push_read(line => "\n\n", sub {
            my($handle, $line) = @_;
            my $res = HTTP::Response->parse($line);
            unless ($res->header('X-WNI-Result') eq 'OK') {
                return $self->on_error->("Authentication failed.");
            }

            my $reader; $reader = sub {
                my($handle, $line) = @_;
                warn $line;

                my $req = HTTP::Request->parse($line);
                if ($req->header('X-WNI-ID') eq 'Data') {
                    my $length = $req->content_length
                        or return $self->on_error->("Content-Length not found: $line");
                    $handle->unshift_read(chunk => $length, sub {
                        my $data = $_[1];
                        warn $data;
                        # parse EEW
                    });
                } elsif ($req->header('X-WNI-ID') eq 'Keep-Alive') {
                    # do nothing
                } else {
                    return $self->on_error->("Unknown HTTP request: $line");
                }

                my $res = HTTP::Headers->new(
                    'Content-Type'           => 'application/fast-cast',
                    'Server'                 => 'FastCaster/1.0.0 (Unix)',
                    'X-WNI-ID'               => 'Response',
                    'X-WNI-Result'           => 'OK',
                    'X-WNI-Protocol-Version' => '2.1',
                    'X-WNI-Time'             => DateTime->now->strftime('%Y/%m/%d %H:%M:%S.%6N'),
                );
                $handle->push_write("HTTP/1.0 200 OK\n");
                $handle->push_write($res->as_string);
                $handle->push_write("\n");

                $handle->push_read(line => "\n\n", $reader);
            };
            $handle->push_read(line => "\n\n", $reader);
        });
    };
}

no Any::Moose;

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

Net::WeatherNews::QuakeWarning - Receives Weather News earthquake warning

=head1 SYNOPSIS

  use Net::WeatherNews::QuakeWarning;

  my $client = Net::WeatherNews::QuakeWarning->new(
      email => "your-account",
      password => "your-password",
      on_warning => sub {
          my $info = shift;
          warn "An M$info->{magnitude}/SI$info->{shindo} earthquake happened in ",
              "$info->{eq_place} ($info->{center_lat}/$info->{center_lng})\n"
          for my $place (values %{$info->{EBI}}) {
              warn "It will hit $place->{name} in $place->{time} as big as SI $place->{shindo1}\n";
          }
      },
  );

  my $guard = $client->connect;

  AnyEvent->condvar->recv;

=head1 DESCRIPTION

Net::WeatherNews::QuakeWarning is a module to connect and wait for
Weather News' early earthquake warnings aka I<Last 10 seconds>
notification.

L<http://weathernews.jp/quake/>

This module uses AnyEvent underneath as an event loop, so you should
create your own AnyEvent event loop yourself, or use whatever
supported backends like POE or EV.

In the callback you can automate your stuff to do when a big quake is
coming, hopefully using other AnyEvent libraries: Growl, send an SMS
to your phone, beep system sound, shutdown your other computer, launch
an iSight to capture the shake, or send a good-bye email to your
significant other (hopefully not!).

See L<http://shibuya246.com/2009/08/11/earthquake-news/> how this
early warning system works. This is not a prediction but a warning.

=head1 AUTHOR

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt>

Satoshi Kubota made the library to parse EEW Data format as well as reverse
engineered the WNI fast-cast protocol at L<http://github.com/skubota/eewdata/>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<http://github.com/skubota/eewdata/>

=cut
