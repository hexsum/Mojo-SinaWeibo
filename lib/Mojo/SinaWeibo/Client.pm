package Mojo::SinaWeibo::Client;
use Mojo::SinaWeibo::Client::Remote::_prelogin;
use Mojo::SinaWeibo::Client::Remote::_get_pin;
use Mojo::SinaWeibo::Client::Remote::_login;
use Mojo::SinaWeibo::Message::Handle;

sub ready{
    my $self = shift;
    my $plugins = $self->plugins;
    my $plugins = $self->plugins;
    for(
        sort {$plugins->{$b}{priority} <=> $plugins->{$a}{priority} }
        grep {defined $plugins->{$_}{auto_call} and $plugins->{$_}{auto_call} == 1} keys %{$plugins}
    ){
        $self->call($_);
    }
    $self->emit("after_load_plugin");
    $self->is_ready(1);
    $self->emit("ready");
}
sub run{
    my $self = shift;
    $self->ready() if not $self->is_ready;
    $self->emit("run");
    $self->ioloop->start unless $self->ioloop->is_running;
}

sub timer {
    my $self = shift;
    return $self->ioloop->timer(@_);
}
sub interval{
    my $self = shift;
    return $self->ioloop->recurring(@_);
}

sub stop {
    my $self = shift;
    $self->is_stop(1);
    $self->info("客户端停止运行");
    CORE::exit();
}

sub login{
    my $self = shift;
    my $prelogin_info = $self->_prelogin();
    if(not defined $prelogin_info){
        $self->error("登录准备过程异常，客户端退出");
        $self->stop();
    }
    my $need_pin = 0;
    my $verifycode;
    while(1){
        my $login_info = $self->_login(
            account     => $self->account,
            pwd         => $self->pwd,
            pwencode    => 'rsa',
            servertime  => $prelogin_info->{servertime},
            nonce       => $prelogin_info->{nonce},
            exectime    => $prelogin_info->{exectime},
            rsakv       => $prelogin_info->{rsakv},
            pubkey      => $prelogin_info->{pubkey},
            need_pin    => $need_pin,
            verifycode  => $verifycode,
            pcid        => $prelogin_info->{pcid},
            returntype  => 'META',
        );
        if(not defined $login_info){
            $self->error("登录失败，客户端退出");
            $self->stop();
        }
        elsif($login_info->{retcode} == 0){
            $self->user->id($login_info->{id});
            $self->user->nick($login_info->{nick});
            $self->user->home($login_info->{home});
            $self->user->ticket($login_info->{ticket});
            $self->info("登录成功");
            return 1;
        }
        elsif($login_info->{retcode} == 1){
            $verifycode = $self->_get_pin(pcid=>$prelogin_info->{pcid});
            $need_pin = 1;
        }
        else{
            $self->error("登录异常，客户端退出");
            $self->stop();
        }
    }
}
1;
