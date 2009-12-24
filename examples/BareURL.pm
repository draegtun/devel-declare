package BareURL;
use Modern::Perl;
use Devel::Declare ();
use LWP::Simple ();
use base 'Devel::Declare::Context::Simple';

sub import {
    my $class  = shift;
    my $caller = caller;
    my $ctx    = __PACKAGE__->new;

    Devel::Declare->setup_for(
        $caller,
        {
            http => {
                const => sub { $ctx->parser(@_) },
            },
        },
    );

    no strict 'refs';
    *{$caller.'::http'} = sub ($) { LWP::Simple::get( $_[0] ) };
}

sub parser {
    my $self = shift;
    $self->init(@_);
    $self->skip_declarator;          # skip past "http"

    my $line = $self->get_linestr;   # get me current line of code
    my $pos  = $self->offset;        # position just after "http"
    my $url  = substr $line, $pos;   # url & everything after "http"

    for my $c (split //, $url) {
        # if blank, semicolon, closing parenthesis or a comma(!) then no longer a URL
        last if $c eq q{ };
        last if $c eq q{;};
        last if $c eq q{)};
        last if $c eq q{,};
        $pos++;
    }    

    # wrap the url with http() sub and quotes
    substr( $line, $pos,          0 ) = q{")};
    substr( $line, $self->offset, 0 ) = q{("http};

    # pass back changes to parser
    $self->set_linestr( $line );

    return;
}

# see:  http://transfixedbutnotdead.com/2009/12/16/url-develdeclare-and-no-strings-attached/

1;