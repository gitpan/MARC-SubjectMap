package MARC::SubjectMap::Rule;

use strict;
use warnings;
use base qw( Class::Accessor );
use MARC::SubjectMap::XML qw( element startTag endTag );

=head1 NAME

MARC::SubjectMap::Rule - a transformation rule

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=head2 field()

=head2 subfield()

=head2 original()

=head2 translation()

=head2 source()

=cut 

my @fields = qw( field subfield original translation source );

__PACKAGE__->mk_accessors( @fields );

sub toString {
    my $self = shift;
    my @chunks = ();
    foreach my $field ( @fields ) {
        push( @chunks, "$field: " . exists($self->{$field}) ? 
            $self->{field} : "" );
    }
    return join( "; ", @chunks ); 
}

sub toXML {
    my $self = shift;
    my $xml = startTag( "rule", field => $self->field(), 
        subfield => $self->subfield() ) . "\n";
    $xml .= element( "original", $self->original() ) . "\n";
    $xml .= element( "translation", $self->translation() ) . "\n";
    $xml .= element( "source", $self->source() ) . "\n";
    $xml .= endTag( "rule" ) . "\n";
    return $xml;
}

1;

