package Devel::Declare::Context::Simple;

use strict;
use warnings;
use Devel::Declare ();
use B::Hooks::EndOfScope;
use Carp qw/confess/;

sub new {
  my $class = shift;
  bless {@_}, $class;
}

sub init {
  my $self = shift;
  @{$self}{ qw(Declarator Offset) } = @_;
  return $self;
}

sub offset {
  my $self = shift;
  return $self->{Offset}
}

sub inc_offset {
  my $self = shift;
  $self->{Offset} += shift;
}

sub declarator {
  my $self = shift;
  return $self->{Declarator}
}

sub skip_declarator {
  my $self = shift;
  my $decl = $self->declarator;
  my $len = Devel::Declare::toke_scan_word($self->offset, 0);
  confess "Couldn't find declarator '$decl'"
    unless $len;

  my $linestr = $self->get_linestr;
  my $name = substr($linestr, $self->offset, $len);
  confess "Expected declarator '$decl', got '${name}'"
    unless $name eq $decl;

  $self->inc_offset($len);
}

sub skipspace {
  my $self = shift;
  $self->inc_offset(Devel::Declare::toke_skipspace($self->offset));
}

sub get_linestr {
  my $self = shift;
  my $line = Devel::Declare::get_linestr();
  return $line;
}

sub set_linestr {
  my $self = shift;
  my ($line) = @_;
  Devel::Declare::set_linestr($line);
}

sub strip_name {
  my $self = shift;
  $self->skipspace;
  if (my $len = Devel::Declare::toke_scan_word( $self->offset, 1 )) {
    my $linestr = $self->get_linestr();
    my $name = substr( $linestr, $self->offset, $len );
    substr( $linestr, $self->offset, $len ) = '';
    $self->set_linestr($linestr);
    return $name;
  }

  $self->skipspace;
  return;
}

sub strip_ident {
  my $self = shift;
  $self->skipspace;
  if (my $len = Devel::Declare::toke_scan_ident( $self->offset )) {
    my $linestr = $self->get_linestr();
    my $ident = substr( $linestr, $self->offset, $len );
    substr( $linestr, $self->offset, $len ) = '';
    $self->set_linestr($linestr);
    return $ident;
  }

  $self->skipspace;
  return;
}

sub strip_proto {
  my $self = shift;
  $self->skipspace;

  my $linestr = $self->get_linestr();
  if (substr($linestr, $self->offset, 1) eq '(') {
    my $length = Devel::Declare::toke_scan_str($self->offset);
    my $proto = Devel::Declare::get_lex_stuff();
    Devel::Declare::clear_lex_stuff();
    $linestr = $self->get_linestr();

    substr($linestr, $self->offset, $length) = '';
    $self->set_linestr($linestr);

    return $proto;
  }
  return;
}

sub strip_names_and_args {
  my $self = shift;
  $self->skipspace;

  my @args;

  my $linestr = $self->get_linestr;
  if (substr($linestr, $self->offset, 1) eq '(') {
    # We had a leading paren, so we will now expect comma separated
    # arguments
    substr($linestr, $self->offset, 1) = '';
    $self->set_linestr($linestr);
    $self->skipspace;

    # At this point we expect to have a comma-separated list of
    # barewords with optional protos afterward, so loop until we
    # run out of comma-separated values
    while (1) {
      # Get the bareword
      my $thing = $self->strip_name;
      # If there's no bareword here, bail
      confess "failed to parse bareword. found ${linestr}"
        unless defined $thing;

      $linestr = $self->get_linestr;
      if (substr($linestr, $self->offset, 1) eq '(') {
        # This one had a proto, pull it out
        push(@args, [ $thing, $self->strip_proto ]);
      } else {
        # This had no proto, so store it with an undef
        push(@args, [ $thing, undef ]);
      }
      $self->skipspace;
      $linestr = $self->get_linestr;

      if (substr($linestr, $self->offset, 1) eq ',') {
        # We found a comma, strip it out and set things up for
        # another iteration
        substr($linestr, $self->offset, 1) = '';
        $self->set_linestr($linestr);
        $self->skipspace;
      } else {
        # No comma, get outta here
        last;
      }
    }

    # look for the final closing paren of the list
    if (substr($linestr, $self->offset, 1) eq ')') {
      substr($linestr, $self->offset, 1) = '';
      $self->set_linestr($linestr);
      $self->skipspace;
    }
    else {
      # fail if it isn't there
      confess "couldn't find closing paren for argument. found ${linestr}"
    }
  } else {
    # No parens, so expect a single arg
    my $thing = $self->strip_name;
    # If there's no bareword here, bail
    confess "failed to parse bareword. found ${linestr}"
      unless defined $thing;
    $linestr = $self->get_linestr;
    if (substr($linestr, $self->offset, 1) eq '(') {
      # This one had a proto, pull it out
      push(@args, [ $thing, $self->strip_proto ]);
    } else {
      # This had no proto, so store it with an undef
      push(@args, [ $thing, undef ]);
    }
  }

  return \@args;
}

sub strip_attrs {
  my $self = shift;
  $self->skipspace;

  my $linestr = Devel::Declare::get_linestr;
  my $attrs   = '';

  if (substr($linestr, $self->offset, 1) eq ':') {
    while (substr($linestr, $self->offset, 1) ne '{') {
      if (substr($linestr, $self->offset, 1) eq ':') {
        substr($linestr, $self->offset, 1) = '';
        Devel::Declare::set_linestr($linestr);

        $attrs .= ':';
      }

      $self->skipspace;
      $linestr = Devel::Declare::get_linestr();

      if (my $len = Devel::Declare::toke_scan_word($self->offset, 0)) {
        my $name = substr($linestr, $self->offset, $len);
        substr($linestr, $self->offset, $len) = '';
        Devel::Declare::set_linestr($linestr);

        $attrs .= " ${name}";

        if (substr($linestr, $self->offset, 1) eq '(') {
          my $length = Devel::Declare::toke_scan_str($self->offset);
          my $arg    = Devel::Declare::get_lex_stuff();
          Devel::Declare::clear_lex_stuff();
          $linestr = Devel::Declare::get_linestr();
          substr($linestr, $self->offset, $length) = '';
          Devel::Declare::set_linestr($linestr);

          $attrs .= "(${arg})";
        }
      }
    }

    $linestr = Devel::Declare::get_linestr();
  }

  return $attrs;
}


sub get_curstash_name {
  return Devel::Declare::get_curstash_name;
}

sub shadow {
  my $self = shift;
  my $pack = $self->get_curstash_name;
  Devel::Declare::shadow_sub( $pack . '::' . $self->declarator, $_[0] );
}

sub inject_if_block {
  my $self   = shift;
  my $inject = shift;
  my $before = shift || '';

  $self->skipspace;

  my $linestr = $self->get_linestr;
  if (substr($linestr, $self->offset, 1) eq '{') {
    substr($linestr, $self->offset + 1, 0) = $inject;
    substr($linestr, $self->offset, 0) = $before;
    $self->set_linestr($linestr);
    return 1;
  }
  return 0;
}

sub scope_injector_call {
  my $self = shift;
  my $inject = shift || '';
  return ' BEGIN { ' . ref($self) . "->inject_scope('${inject}') }; ";
}

sub inject_scope {
  my $class = shift;
  my $inject = shift;
  on_scope_end {
      my $linestr = Devel::Declare::get_linestr;
      return unless defined $linestr;
      my $offset  = Devel::Declare::get_linestr_offset;
      substr( $linestr, $offset, 0 ) = ';' . $inject;
      Devel::Declare::set_linestr($linestr);
  };
}

1;
# vi:sw=2 ts=2

__END__

=head1 NAME

Devel::Declare::Context::Simple - Parser utilities for Devel::Declare

=head1 VERSION

See Devel::Declare


=head1 SYNOPSIS

Devel::Declare::Context::Simple is a base class:


    package Foo;
    use Devel::Declare ();
    use base 'Devel::Declare::Context::Simple';
    
    sub import {
        my $class = shift;
        my $ctx   = __PACKAGE__->new;
        
        ... Devel::Declare stuff ...
    }
    
    

=head1 DESCRIPTION

The Devel::Declare::Context::Simple base class help maintains parsing state and provides handy utility methods.

    package Shout;
    use Devel::Declare ();
    use base 'Devel::Declare::Context::Simple';

    sub import {
        my $class  = shift;
        my $caller = caller;
        my $ctx    = __PACKAGE__->new;

        Devel::Declare->setup_for(
            $caller,
            {
                shout => {
                    const => sub { $ctx->parser(@_) },
                },
            },
        );

        no strict 'refs';
        *{$caller.'::shout'} = sub ($) { uc $_[0] ) };
    }

    sub parser {
        my $self = shift;
        $self->init(@_);
        $self->skip_declarator;          # skip past "shout"
        $self->skipspace;
        
        my $line = $self->get_linestr;   # get me current line of code

        # insert q 
        substr( $line, $self->offset, 0 ) = ' q';

        # pass back to parser
        $self->set_linestr( $line );
    }

    1;

Then later:

    use Shout;
    
    shout/say this out loud!/;      # => SAY THIS OUT LOUD!
    
    # Because Devel::Declare converted this to:   shout q/say this out loud!/;
    
    

=head1 EXPORT

None.


=head1 ATTRIBUTES

=head2 Declarator

The declarator name, ie. the new keyword (token) we declared.

=head2 Offset

Initially this is the position from beginning of line where the declarator was found.

NB. There should be no need to amend these attributes manually.  Leave it all to methods below.


=head1 METHODS

=head2 new

Your normal constructor.

=head2 init

Initialise the L<"Declarator"> and L<"Offset">  attributes for this parse.

=head2 offset

Returns the L<"Offset"> attribute for current parse.

    my $current_position = $self->offset;

=head2 inc_offset

Increments the L<"Offset">.

    $self->inc_offset( 10 );   # move offset 10 characters on.


=head2 declarator

Returns the L<"Declarator"> attribute for current parse

    my $which_keyword_was_just_parsed = $self->declarator;


=head2 skip_declarator

Make the parser skip past the declarator.  The L<"Offset"> attribute now points to next character after it.

    sub parser {
        my $self = shift;
        $self->init(@_);
        
        my $declarator_pos = $self->offset;  # points to first char of declarator
        
        $self->skip_declarator;              # skip past declarator
        
        my $pos_straight_after_declarator = $self->offset;
    }


=head2 skipspace

Makes the parser skip any whitespace.

    $self->skipspace;
    
    my $now_on_next_non_whitespace_char = $self->offset;



=head2 get_linestr 

Get the complete line of code that the parser as hit.

    my $line_of_code = $self->get_linestr;



=head2 set_linestr

Replaces the current line of code.  This is the code that Perl will compile.

    $self->set_linestr( $my_new_line_of_code );


=head2 strip_name

Will strip out the next 'token' it finds, return it and update L<"Offset"> accordingly.

This is useful for parsing things like.

    func shout { ... }

Where 'func' triggered the parser: 
        
    $self->skip_declarator;         # skip past 'func' declarator
    
    my $name = $self->strip_name;   # this strips & returns 'shout'
    
    my $line = $self->get_linestr;  # this will now look like:  func { }
    
    my $pos = $self->offset;        # will be pointing at space just after 'func'



=head2 strip_ident

TBD.

=head2 strip_proto

Strips and returns next bit of code if it looks like sub proto (ie. something within parenthesis) 

This is useful for parsing things like:

    func shout($x,$y) { ... }
    
Which would be done like this:

    $self->skip_declarator;         # skip past 'func' declarator

    my $name = $self->strip_name;   # this strips & returns:  shout
    
    my $proto = $self->strip_proto; # strips and returns:    $x,$y

    my $line = $self->get_linestr;  # this will now look like:  func { }


=head2 strip_names_and_args 

This is like L<"strip_name"> but also parses the proto declaration.

For eg:

    func shout(Str $x, Int $y) { ... }
    
Then:

    my $args = $self->strip_names_and_args;     # strips and returns array_ref with args

    # $args =>
    # [
    #   [ 'Str', '$x' ],
    #   [ 'Int', '$y' ],
    # ]

NB. Note to myself... double check this is how it works :)


=head2 strip_attrs 

Strips and returns next bit of code if it looks like a sub attribute.

For eg:

    func shout : attr1 { ... }
    
    # or
    
    func shout() : attr1 { ... }
    
Then:

    my $proto = $self->strip_proto; # just in case!
    
    my $attr = $self->strip_attr;   # strips and returns:    attr1
    

=head2 get_curstash_name

This returns the package name currently being compiled.


=head2 shadow

Need my brain in gear to document this bit properly!

Shadow sub replacement method.


=head2 inject_if_block

Injects extra code into the start of a block.

For eg.

    func shout { ... }
    
Then.

    $self->inject_if_block( ' my $self = shift; ' );
    
Would transform it to:

    func shout { my $self = shift; ... }



=head2 scope_injector_call

See L<Devel::Declare/"scope_injector_call"> for a complete description.



=head2 inject_scope

Again, see L<Devel::Declare/"scope_injector_call"> for full info.




=head1 AUTHORS

Matt S Trout - E<lt>mst@shadowcat.co.ukE<gt> - original author

Florian Ragwitz E<lt>rafl@debian.orgE<gt> - maintainer

osfameron E<lt>osfameron@cpan.orgE<gt> - first draft of documentation

Barry Walsh, C<< <draegtun at cpan.org> >> - first draft of D::D::Context::Simple docs


=head1 COPYRIGHT AND LICENSE

This library is free software under the same terms as perl itself

Copyright (c) 2007, 2008, 2009  Matt S Trout

Copyright (c) 2008, 2009  Florian Ragwitz

stolen_chunk_of_toke.c based on toke.c from the perl core, which is

Copyright (C) 1991, 1992, 1993, 1994, 1995, 1996, 1997, 1998, 1999,
2000, 2001, 2002, 2003, 2004, 2005, 2006, by Larry Wall and others
