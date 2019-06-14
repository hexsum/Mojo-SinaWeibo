package Mojo::SinaWeibo::User;
use Mojo::Base 'Mojo::SinaWeibo::Model::Base';
has [qw(
    id
    home
    nick
    ticket
)];
sub displayname {
    my $self = shift;
    return $self->nick || '昵称未知';
}
1;
