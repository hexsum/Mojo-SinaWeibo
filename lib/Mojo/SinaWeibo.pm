package Mojo::SinaWeibo;
$Mojo::SinaWeibo::VERSION = "1.7";
use Carp ();
use POSIX ();
use File::Spec ();
use Mojo::IOLoop;
use Mojo::SinaWeibo::Log;
use Mojo::Base 'Mojo::EventEmitter';

use base qw(Mojo::SinaWeibo::Util Mojo::SinaWeibo::Model Mojo::SinaWeibo::Client Mojo::SinaWeibo::Plugin Mojo::SinaWeibo::Request);

has 'account';
has 'pwd';
has ua_debug    => 0;
has ua_debug_req_body   => sub{$_[0]->ua_debug};
has ua_debug_res_body   => sub{$_[0]->ua_debug};
has log_level   => 'info'; #debug|info|warn|error|fatal
has log_path    => undef;
has log_encoding => undef;
has ioloop      => sub {Mojo::IOLoop->singleton};

has user => sub{$_[0]->new_user};

has tmpdir              => sub {File::Spec->tmpdir();};
has media_dir           => sub {$_[0]->tmpdir};
has cookie_dir          => sub{return $_[0]->tmpdir;};
has qrcode_path         => sub {File::Spec->catfile($_[0]->tmpdir,join('','mojo_sinaweibo_qrcode_',$_[0]->account || 'default','.png'))};
has verifycode_path         => sub {File::Spec->catfile($_[0]->tmpdir,join('','mojo_sinaweibo_verifycode_',$_[0]->account || 'default','.png'))};
has keep_cookie         => 1;

has version => $Mojo::SinaWeibo::VERSION;
has plugins => sub{+{}};

has is_ready                => 0;
has is_stop                 => 0;
has ua_retry_times          => 5;
has is_first_login          => -1;

has message_queue => sub{$_[0]->gen_message_queue()};

has login_state             => 'init';
has log         => sub {
    Mojo::SinaWeibo::Log->new(
        encoding    =>  $_[0]->log_encoding,
        path        =>  $_[0]->log_path,
        level       =>  $_[0]->log_level,
        format      =>  sub{
            my ($time, $level, @lines) = @_;
            my $title = "";
            my $truncate = 0;
            if(ref $lines[0] eq "HASH"){
                my $opt = shift @lines; 
                $time = $opt->{"time"} if defined $opt->{"time"};
                $title = $opt->{title} . " " if defined $opt->{"title"};
                $level  = $opt->{level} if defined $opt->{"level"};
                $truncate  = $opt->{truncate} if defined $opt->{"truncate"};
            }
            @lines = split /\n/,join "",@lines;
            my $return = "";
            $time = $time?POSIX::strftime('[%y/%m/%d %H:%M:%S]',localtime($time)):"";
            $level = $level?"[$level]":"";
            for(@lines){$return .= $time . " " . $level . " " . $title . $_ . "\n";}
            return length($return) > $truncate?substr($return,0,$truncate) . "...\n" : $return if $truncate;
            return $return;
        }
    )
};

has ua                      => sub {
    #local $ENV{MOJO_USERAGENT_DEBUG} = $_[0]->ua_debug;
    require Mojo::UserAgent;
    require Storable if $_[0]->keep_cookie;
    Mojo::UserAgent->new(
        max_redirects      => 7,
        request_timeout    => 120,
        inactivity_timeout => 120,
        transactor => Mojo::UserAgent::Transactor->new( 
            name =>  'Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/37.0.2062'
        ),
    );
};

sub on {
    my $self = shift;
    my @return;
    while(@_){
        my($event,$callback) = (shift,shift);
        push @return,$self->SUPER::on($event,$callback);
    }
    return wantarray?@return:$return[0];
}
sub emit {
    my $self = shift;
    $self->SUPER::emit(@_);
    $self->SUPER::emit(all_event=>@_);
}

sub wait_once {
    my $self = shift;
    my($timeout,$timeout_callback,$event,$event_callback)=@_;
    my ($timer_id, $subscribe_id);
    $timer_id = $self->timer($timeout,sub{
        $self->unsubscribe($event,$subscribe_id);
        $timeout_callback->(@_) if ref $timeout_callback eq "CODE";
    });
    $subscribe_id = $self->once($event=>sub{
        $self->ioloop->remove($timer_id);
        $event_callback->(@_) if ref $event_callback eq "CODE";
    });
    $self;
}

sub wait {
    my $self = shift;
    my($timeout,$timeout_callback,$event,$event_callback)=@_;
    my ($timer_id, $subscribe_id);
    $timer_id = $self->timer($timeout,sub{
        $self->unsubscribe($event,$subscribe_id);
        $timeout_callback->(@_) if ref $timeout_callback eq "CODE";;
    });
    $subscribe_id = $self->on($event=>sub{
        my $ret = ref $event_callback eq "CODE"?$event_callback->(@_):0;
        if($ret){ $self->ioloop->remove($timer_id);$self->unsubscribe($event,$subscribe_id); }
    });
    $self;
}

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    #$ENV{MOJO_USERAGENT_DEBUG} = $self->{ua_debug};
    $self->info("当前正在使用 Mojo-SinaWeibo v" . $self->version);
    $self->ioloop->reactor->on(error=>sub{
        my ($reactor, $err) = @_;
        $self->error("reactor error: " . Carp::longmess($err));
    });
    $SIG{__WARN__} = sub{$self->warn(Carp::longmess @_);};
    $self->on(error=>sub{
        my ($self, $err) = @_;
        $self->error(Carp::longmess($err));
    });
    $Mojo::SinaWeibo::_CLIENT = $self;
    if(not defined $self->account or not defined $self->pwd){
        $self->error("请设置登录帐号或密码");
        $self->stop();
    }
    $self;
}

1;
