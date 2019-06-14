package Mojo::SinaWeibo::Message;
use Mojo::Base -base;
has id   => sub{int(rand(10000)) };
has time => sub{time};
has code => 0;
has ttl => 5;
has source => 'local';
has 'cb';
has from => 'none';
has allow_plugin => 1;
has [qw(content class type)];
has status => '';

sub is_success{
    my $self = shift;
    return $self->code == 100000?1:0;
}
1;
