package MARC::SubjectMap;

use strict;
use warnings;
use Carp qw( croak );
use MARC::Field;
use MARC::SubjectMap::XML qw( startTag endTag );
use MARC::SubjectMap::Rules;
use MARC::SubjectMap::Handler;
use XML::SAX::ParserFactory;
use IO::File;

our $VERSION = '0.4';

=head1 NAME

MARC::SubjectMap - framework for translating subject headings

=head1 SYNOPSIS 

    use MARC::SubjectMap;
    my $map = MARC::SubjectMap->newFromConfig( "config.xml" );

    my $batch = MARC::Batch->new( 'USMARC', 'batch.dat' );
    while ( my $record = $batch->next() ) {
        my $new = $map->translateRecord( $record );
        ...
    }

=head1 DESCRIPTION

MARC::SubjectMap is a framework for providing translations of subject
headings. MARC::SubjectMap is essentially a configuration which contains
a list of fields/subfields to translate or copy, and a list of rules
for translating one field/subfield value into another.

Typical usage of the framework will be to use the C<subjmap-template>
command line application to generate a template XML configuration from a 
batch of MARC records. You tell C<subjmap-template> the fields you'd like
to translate and/or copy and it will look through the records and extract
and add rule templates for the unique values. For example:

    subjmap-template --in=marc.dat --out=config.xml --translate=650ab 

Once the template configuration has been filled in with translations,
the MARC batch file can be run through another command line utility called
C<subjmap> which will add new subject headings where possible using 
the configuration file. If a subject headings can't be translated it will be 
logged to a file so that the configuration file can be improved if necessary. 
    
    subjmap --in=marc.dat --out=new.dat --config=config.xml --log=log.txt

The idea is that all the configuration is done in the XML file, and the
command line programs take care of driving these modules for you. Methods
and related modules are listed below for the sake of completeness, and if
you want to write your own driving program for some reason.

=head1 METHODS

=head2 new()

The constructor which accepts no arguments.

=cut 

sub new {
    my ($class) = @_;
    my $self = bless { fields => [] }, ref($class) || $class;
    return $self;
}

=head2 newFromConfig()

Factory method for creating a MARC::SubjectMap object from an XML 
configuration. If there is an error you will get it on STDERR.

    my $mapper = MARC::SubjectMap->new( 'config.xml' ); 

=cut

sub newFromConfig {
    my ($package,$file) = @_; 
    my $handler = MARC::SubjectMap::Handler->new();
    my $parser = XML::SAX::ParserFactory->parser( Handler => $handler );
    eval { $parser->parse_uri( $file ) };
    croak( "invalid configuration file: $file: $@" ) if $@;
    return $handler->config();
}

=head2 writeConfig()

Serializes the configuration to disk as XML.

=cut 

sub writeConfig {
    my ($self,$file) = @_;
    my $fh = IO::File->new( ">$file" ) 
        or croak( "unable to write to file $file: $! " );
    $self->toXML($fh);
}

=head2 addField()

Adds a field specification to the configuration. Each specification defines the
fields and subfields to look for and copy/translate in MARC data. The 
information is bundled up in a MARC::SubjectMap::Field object.

=cut 

sub addField {
    my ($self,$field) = @_;
    croak( "must supply MARC::SubjectMap::Field object" ) 
        if ref($field) ne 'MARC::SubjectMap::Field';
    push( @{ $self->{fields} }, $field );
}

=head2 fields()

Returns a list of MARC::SubjectMap::Field objects which specify the
fields/subfields in MARC data that will be copied and/or translated.

=cut 

sub fields {
    my ($self) = @_;
    return @{ $self->{fields} };
}

=head2 rules()

Get/set the rules being used in this configuration. You should pass
in a MARC::SubjectMap::Rules object if you are setting the rules.

    $map->rules( $rules );

The reason why a sepearte object is used to hold the Rules as opposed to the
fields being contained in the MARC::SubjectMap object is that there can be 
many (thousands perhaps) of rules -- which need to be stored differently than
the handful of fields. 

=cut

sub rules {
    my ($self,$rules) = @_;
    croak( "must supply MARC::SubjectMap::Rules object if setting rules" )
        if $rules and ref($rules) ne 'MARC::SubjectMap::Rules';
    $self->{rules} = $rules if $rules;
    return $self->{rules};
}

=head2 translateRecord()

Accepts a MARC::Record object and returns a translated version of it
if there were any translations that could be performed. If no translations
were possible undef will be returned.

=cut

sub translateRecord {
    my ($self,$record) = @_;
    croak( "must supply MARC::Record object to translateRecord()" )
        if ! ref($record) or ! $record->isa( 'MARC::Record' );

    ## create a copy of the record to add to
    my $clone = $record->clone();
    my $found = 0;
    foreach my $field ( $self->fields() ) { 
        my @marcFields = $record->field( $field->tag() );
        my $fieldCount = 0;
        foreach my $marcField ( @marcFields ) {
            $fieldCount++;
            my $new = $self->translateField($marcField);
            if ( $new ) { 
                $clone->insert_grouped_field($new);
                $found = 1;
            } 
            else {
                my $control = $record->field('001') ? 
                    $record->field('001')->data() : '';
                my $suffix = $fieldCount == 1 ? 'st' : $fieldCount == 2 ? 'nd' 
                    : $fieldCount == 3 ? 'rd' : 'th';
                $self->log( "couldn't translate $fieldCount$suffix ".
                    $field->tag() . " in record with 001 $control" );
            }
        }
    }
    return $clone if $found;
    return;
}

=head2 translateField()

Accepts a MARC::Field object and returns a translated version of it if it can
be translated. If it can't be translated then undef is returned.

=cut 

sub translateField {
    my ($self,$field) = @_;
    croak( "must supply MARC::Field object to translateField()" )
        if ! ref($field) or ! $field->isa( 'MARC::Field' );

    ## subfields with subfield 2 already present are not translated
    return if $field->subfield(2);

    ## only lcsh subject headings are translated
    return if $field->indicator(2) ne '0';

    my @subfields;
    my %sources;
    foreach my $subfield ( $field->subfields() ) {
        my $rule = $self->{rules}->getRule( 
            field       => $field->tag(),
            subfield    => $subfield->[0], 
            original    => $subfield->[1], );
        if ( $rule ) { 

            ## must have translation
            if ( $rule->translation() ) {
                push( @subfields, $subfield->[0], $rule->translation() );
            } else {
                $self->log( "missing translation for rule: ".$rule->toString());
            }

            ## must have source for translation
            if ( $rule->source() ) { 
                $sources{ $rule->source() } = 1;
            } else {
                $self->log( "missing source for rule: ".$rule->toString() );
            }
        }
        else {
            $self->log( 
                "no rule for field=" . $field->tag() .
                " subfield=" . $subfield->[0] . 
                " value=".$subfield->[1] 
            );
            return;
        }
    }

    ## if the subfield doesn't end in a period or a right paren add a period
    $subfields[-1] .= '.' if ( $subfields[-1] !~ /[.)]/ );
    ## add source of translations to the field
    push( @subfields, '2', $_ ) for keys(%sources);
    return MARC::Field->new($field->tag(),$field->indicator(1),7,@subfields);
}

=head2 setLog()

Set a file to send diagnostic messages to. If unspecified messages will go to
STDERR. Alternatively you can pass in a IO::Handle object. 

=cut

## logging methods

sub setLog {
    my ($self,$f) = @_;
    if ( ref($f) ) {
        $self->{log} = $f; 
    } else {
        $self->{log} = IO::File->new( ">$f" );
    }
}

sub log {
    my ($self,$msg) = @_;
    my $string = localtime().": $msg\n";
    if ( $self->{log} ) {
        $self->{log}->print( $string );
    } else {
        print STDERR $string;
    }
}

# returns entire object as XML
# this is essentially the configuration
# since it can be big a filehandle must be passed in

sub toXML {
    my ($self,$fh) = @_;
    print $fh qq(<?xml version="1.0" encoding="ISO-8859-1"?>\n);
    print $fh startTag( "config" ),"\n\n";

    ## add fields
    print $fh startTag( "fields" ), "\n\n";
    foreach my $field ( $self->fields() ) {
        print $fh $field->toXML(), "\n";
    }
    print $fh endTag( "fields" ), "\n\n";

    ## add rules
    if ( $self->rules() ) { 
        $self->rules()->toXML( $fh );
    }

    print $fh "\n", endTag( "config" ), "\n";
}


sub DESTROY {
    my $self = shift;
    ## close log file handle if its open
    $self->{log}->close() if exists( $self->{log} ); 
}

=head1 SEE ALSO

=over 4 

=item * L<MARC::SubjectMap::Rules>

=item * L<MARC::SubjectMap::Rule>

=item * L<MARC::SubjectMap::Field>

=head1 AUTHORS

=over 4

=item * Ed Summers <ehs@pobox.com>

=back

=cut

1;
