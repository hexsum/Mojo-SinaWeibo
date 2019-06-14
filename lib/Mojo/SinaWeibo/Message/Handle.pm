package Mojo::SinaWeibo;
use strict;
use Mojo::SinaWeibo::Message;
use Mojo::SinaWeibo::Message::Queue;
$Mojo::SinaWeibo::Message::LAST_DISPATCH_TIME  = undef;
$Mojo::SinaWeibo::Message::SEND_INTERVAL  = 3;


sub send_message {
    my $self = shift;
    my $content = shift;
    my $msg = Mojo::SinaWeibo::Message->new(content =>  $content,class=>"send");
    $self->message_queue->put($msg);
}

sub _send_message {
    my $self = shift;
    my $msg = shift;
    my $api = 'http://weibo.com/aj/mblog/add?ajwvr=6&__rnd=' . time . int(rand(1000));
    my $callback = sub{
        my $json = shift;
        return if not defined $json;
        if($json->{code} != 100000 and $msg->ttl < 0 ){
            $self->debug("消息[ " . $msg->id . " ]发送失败，尝试重新发送，当前TTL: " . $msg->ttl);
            $self->message_queue->put($msg);    
            return;
        }
        
        else{
            $msg->code($json->{code});
            $msg->cb->($self,$msg) if ref $msg->cb eq 'CODE';
            $self->emit(send_message => $msg,);
        }

    };
    $self->http_post($api,{Referer=>$self->user->home,json=>1,},form=>{
            location    =>  'v6_content_home',
            appkey      =>  '',
            style_type  =>  1,
            pic_id      =>  '',
            text        =>  $self->decode_utf8($msg->content),
            pdetail     =>  '',
            rank        =>  0,
            rankid      =>  '',
            module      =>  'stissue',
            pub_source  =>  'main_',
            pub_type    =>  'dialog',
            _t          =>  0,
        },$callback
    );
}

sub gen_message_queue{
    my $self = shift;
    Mojo::SinaWeibo::Message::Queue->new(callback_for_get=>sub{
        my $msg = shift;
        return if $self->is_stop;
        if($msg->class eq "send"){
            if($msg->ttl <= 0){
                $msg->code(-1);
                $self->debug("消息[ " . $msg->id.  " ]已被消息队列丢弃，当前TTL: ". $msg->ttl);
                $msg->cb->($self,$msg) if ref $msg->cb eq 'CODE';
                $self->emit(send_message=>$msg); 
                return;
            }

            my $ttl = $msg->ttl;
            $msg->ttl(--$ttl);
            my $delay = 0;
            my $now = time;
            if(defined $Mojo::SinaWeibo::Message::LAST_DISPATCH_TIME){
                $delay = $now<$Mojo::SinaWeibo::Message::LAST_DISPATCH_TIME+$Mojo::SinaWeibo::Message::SEND_INTERVAL?
                            $Mojo::SinaWeibo::Message::LAST_DISPATCH_TIME+$Mojo::SinaWeibo::Message::SEND_INTERVAL-$now
                        :   0;
            }
            $self->timer($delay,sub{
                $msg->time(time);
                $self->_send_message($msg);
            });
            $Mojo::SinaWeibo::Message::LAST_DISPATCH_TIME = $now+$delay;
        }
        elsif($msg->class eq "recv"){
        }
    
    });
}

1;
