package MARC::SubjectMap::Field;

use strict;
use warnings;
use Carp qw( croak );
use MARC::SubjectMap::XML qw( startTag endTag element );

=head1 NAME

MARC::SubjectMap::Field - represent field/subfield combinations to examine

=head1 SYNOPSIS

=head1 DESCRIPTION

The MARC::SubjectMap configuration includes information about which
field/subfield combinations to examine. This is contained in the configuration
as a list of MARC::SubjectMap::Field objects which individually bundle up the
information.

=head1 METHODS

=head2 new()

The constructor. Optionally you can supply tag, translate and copy during the
constructor call instead of using the setters.

    my $f = MARC::Subject::Field->new( { tag => '650', copy => ['a','b'] } )

=cut 

sub new {
    my ( $class, $args ) = @_;
    $args = {} unless ref($args) eq 'HASH';
    my $self = bless $args, ref($class) || $class;
    # set up defaults
    $self->{translate} = [] unless exists( $self->{translate} );
    $self->{copy} = [] unless exists( $self->{copy} );
    return $self;
}

=head2 tag()

Returns the tag for the field, for example: 600 or 650.

=cut

sub tag {
    my ($self,$tag) = @_;
    if ($tag) { $self->{tag} = $tag };
    return $self->{tag};
}

=head2 translate()

Gets a list of subfields to translate in the field.

=cut 

sub translate {
    return @{ shift->{translate} };
}

=head2 addTranslate() 

Adds a subfield to translate.

=cut 

sub addTranslate {
    my ($self,$subfield) = @_;
    croak( "can't both translate and copy subfield $subfield" )
        if grep { $subfield eq $_ } $self->copy();
    push( @{ $self->{translate} }, $subfield ) if defined($subfield);
}

=head2 copy()

Gets a list of subfields to copy in the field.

=cut

sub copy {
    return @{ shift->{copy} };
}

=head2 addCopy() 

Adds a subfield to copy.

=cut

sub addCopy {
    my ($self,$subfield) = @_;
    croak( "can't both copy and translate subfield $subfield" )
        if grep { $subfield eq $_ } $self->translate();
    push( @{ $self->{copy} }, $subfield ) if defined($subfield);
}

sub toXML {
    my $self = shift;
    my $xml = startTag( "field", tag => $self->tag() )."\n";
    map { $xml .= element("copy",$_)."\n" } $self->copy();
    map { $xml .= element("translate",$_)."\n" } $self->translate();
    $xml .= endTag("field")."\n";
    return $xml;
}

1;
