package Gitalist::Controller::Root;

use strict;
use warnings;
use parent 'Catalyst::Controller';

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config->{namespace} = '';

=head1 NAME

Gitalist::Controller::Root - Root Controller for Gitalist

=head1 DESCRIPTION

[enter your description here]

=head1 METHODS

=cut

=head2 index

=cut

#sub index :Path :Args(0) {
#    my ( $self, $c ) = @_;
#
#    # Hello World
#    $c->response->body( $c->welcome_message );
#}

use IO::Capture::Stdout;
sub default :Path {
    my ( $self, $c ) = @_;

	my $capture = IO::Capture::Stdout->new();
	$capture->start();
	eval { gitweb::main() };
	$capture->stop();

	my $output = join '', $capture->read;
    $c->response->body( $output );
}

=head2 end

Attempt to render a view, if needed.

=cut

sub end : ActionClass('RenderView') {}

=head1 AUTHOR

Dan Brook,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
