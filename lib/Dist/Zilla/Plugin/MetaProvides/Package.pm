use strict;
use warnings;

package Dist::Zilla::Plugin::MetaProvides::Package;

# ABSTRACT: Extract namespaces/version from traditional packages for provides
#
# $Id:$
use Moose;
use Moose::Autobox;
use File::Temp qw();
use Module::Extract::VERSION;
use Module::Extract::Namespaces;
use Dist::Zilla::MetaProvides::ProvideRecord 1.13000000;

require Data::Dump;

=head1 SYNOPSIS

In your C<dist.ini>:

    [MetaProvides::Package]
    inherit_version = 0    ; optional
    inherit_missing = 0    ; optional
    meta_noindex    = 1    ; optional

=cut

=head1 ROLES

=head2 L<Dist::Zilla::Role::MetaProvider::Provider>

=cut

use namespace::autoclean;
with 'Dist::Zilla::Role::MetaProvider::Provider';

=head1 OPTIONS INHERITED FROM L<Dist::Zilla::Role::MetaProvider::Provider>

=head2 L<< C<inherit_version>|Dist::Zilla::Role::MetaProvider::Provider/inherit_version >>

How do you want existing versions ( Versions hard-coded into files before running this plug-in )to be processed?

=over 4

=item * DEFAULT: inherit_version = 1

Ignore anything you find in a file, and just probe C<< DZIL->version() >> for a value. This is a sane default and most will want this.

=item * inherit_version = 0

Use this option if you actually want to use hard-coded values in your files and use the versions parsed out of them.

=back

=head2 L<< C<inherit_missing>|Dist::Zilla::Role::MetaProvider::Provider/inherit_missing >>

In the event you are using the aforementioned C<< L</inherit_version> = 0 >>, this determines how to behave when encountering a
module with no version defined.

=over 4

=item * DEFAULT: inherit_missing = 1

When a module has no version, probe C<< DZIL->version() >> for an answer. This is what you want if you want to have some
files with fixed versions, and others to just automatically be maintained by Dist::Zilla.

=item * inherit_missing = 0

When a module has no version, emit a versionless record in the final metadata.

=back

=head2 L<< C<meta_noindex>|Dist::Zilla::Role::MetaProvider::Provider/meta_noindex >>

This is a utility for people who are also using L<< C<MetaNoIndex>|Dist::Zilla::Plugin::MetaNoIndex >>,
so that its settings can be used to eliminate items from the 'provides' list.

=over 4

=item * meta_noindex = 0

By default, do nothing unusual.

=item * DEFAULT: meta_noindex = 1

When a module meets the criteria provided to L<< C<MetaNoIndex>|Dist::Zilla::Plugin::MetaNoIndex >>,
eliminate it from the metadata shipped to L<Dist::Zilla>

=back

=cut

has '+meta_noindex' => ( default => sub { 1 } );

=head1 ROLE SATISFYING METHODS

=head2 provides

A conformant function to the L<Dist::Zilla::Role::MetaProvider::Provider> Role.

=head3 signature: $plugin->provides()

=head3 returns: Array of L<Dist::Zilla::MetaProvides::ProvideRecord>

=cut

sub provides {
    my $self        = shift;
    my $perl_module = sub {
        ## no critic (RegularExpressions)
        $_->name =~ m{^lib[/].*[.](pm|pod)$};
    };
    my $get_records = sub {
        $self->_packages_for( $_->name, $_->content );
    };
    my (@files)   = $self->zilla->files()->flatten;
    my (@records) = @files->grep($perl_module)->map($get_records)->flatten;
    return $self->_apply_meta_noindex(@records);
}

=head1 PRIVATE METHODS

=head2 _packages_for

=head3 signature: $plugin->_packages_for( $filename, $file_content )

=head3 returns: Array of L<Dist::Zilla::MetaProvides::ProvideRecord>

=cut

sub _packages_for {
    my ( $self, $filename, $content, ) = @_;

    my ( $fh, $fn );

  TEMPEXTRACT: {

        $self->log_debug( q{Get packages for } . $filename );
        $fh = File::Temp->new( UNLINK => 0, OPEN => 1, SUFFIX => '.pm' );
        $fh->unlink_on_destroy(1);
        binmode $fh, ':raw';
        print {$fh} $content or $self->log_debug(q{print to filehandle failed});
        close $fh or $self->log_debug(q{closing filehandle failed});
        $fn = $fh->filename;
    }

    # Assumptions: 1 version max per file
    # all packags in that file have that version

    my $version   = Module::Extract::VERSION->parse_version_safely($fn);
    my $to_record = sub {
        my (%struct) = (
            module  => $_,
            file    => $filename,
            version => $version,
            parent  => $self,
        );
        $self->log_debug(
            'Constructing provides record from: ' . Data::Dump::dumpf(
                \%struct,
                sub {
                    my ( $ctx, $objref ) = @_;

                    if ( $ctx->is_hash and $ctx->depth < 1 ) {
                        return;
                    }
                    if ( not defined $objref ) {
                        return { dump => 'undef' };
                    }
                    if ( $ctx->is_scalar and not defined ${$objref} ) {
                        return { dump => 'undef' };
                    }
                    if ( $ctx->is_blessed ) {
                        return { dump => "$objref : " . $ctx->class };
                    }
                    if ( $ctx->is_hash and $ctx->depth >= 1 ) {
                        return { dump => '~Hash' };
                    }
                    if ( $ctx->is_scalar ) {
                        return { dump => "$objref : " . ${$objref} };
                    }
                    return { dump => $ctx->reftype };
                }
            )
        );
        Dist::Zilla::MetaProvides::ProvideRecord->new(%struct);
    };
    my @namespaces = Module::Extract::Namespaces->from_file($fn);
    $self->log_debug( 'Module::Extract::Namespaces discovered namespaces: '
          . Data::Dump::pp( \@namespaces ) . ' in '
          . $fn );
    if ( Module::Extract::Namespaces->error ) {
        $self->log( Module::Extract::Namespaces->error );
    }
    if ( not @namespaces ) {
        $self->log( 'No namespaces detected in file ' . $filename );
        return ();
    }
    return @namespaces->map($to_record)->flatten;

}

=head1 SEE ALSO

=over 4

=item * L<Dist::Zilla::Plugin::MetaProvides>

=back

=cut

__PACKAGE__->meta->make_immutable;
no Moose;
1;

