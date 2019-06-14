package Mojo::SinaWeibo::Model;
use Mojo::SinaWeibo::User;
sub new_user {
    my $self = shift;
    Mojo::SinaWeibo::User->new(@_);
}
1;
