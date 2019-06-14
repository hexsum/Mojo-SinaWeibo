package Mojo::SinaWeibo::Model::Base;
use Mojo::Base -base;
use Data::Dumper;
use Scalar::Util qw(blessed);
use Encode qw(decode_utf8);
use List::Util qw(first);

sub client {
    return $Mojo::SinaWeibo::_CLIENT;
}
sub to_json_hash{
    my $self = shift;   
    my $is_keep_member = shift || 1;
    my $hash = {};
    for(keys %$self){
        next if substr($_,0,1) eq "_";
        next if $_ eq "member";
        $hash->{$_} = decode_utf8($self->{$_});
        $hash->{displayname} = decode_utf8 $self->displayname;
    }
    if($is_keep_member and exists $self->{member} ){
        $hash->{member} = [];
        if(ref $self->{member} eq "ARRAY"){
            for my $m(@{$self->{member}}){
                my $member_hash = $m->to_json_hash();
                push @{$hash->{member}},$member_hash;
            }
        }
    }

    return $hash;
}
sub dump{
    my $self = shift;
    my $clone = {};
    my $obj_name = blessed($self);
    for(keys %$self){
        if(my $n=blessed($self->{$_})){
             $clone->{$_} = "Object($n)";
        }
        elsif($_ eq "member" and ref($self->{$_}) eq "ARRAY"){
            my $member_count = @{$self->{$_}};
            $clone->{$_} = [ "$member_count of Object(${obj_name}::Member)" ];
        }
        else{
            $clone->{$_} = $self->{$_};
        }
    }
    local $Data::Dumper::Indent = 1;
    local $Data::Dumper::Terse = 1;
    $self->client->print("Object($obj_name) " . Data::Dumper::Dumper($clone));
    return $self;
}

sub _add{
    my $self = shift;
    my $array_ref = shift;
    my $element = shift;

    if(@$array_ref == 0){ push @$array_ref,$element; return 3;}
    my $o = first { $element->id eq $_->id } @$array_ref;
    if(defined $o){ $o->update($element);return 2}
    else{ push @$array_ref,$element;return 1}
}
sub _remove{
    my $self = shift;
    my $array_ref = shift;
    my $element = shift;
    for( my $i=0;$i<@$array_ref;$i++ ){
        if($array_ref->[$i]->id  eq $element->id){
            splice @$array_ref,$i,1;
            return 1;
        }
    }
    return 0;
}
sub _search{
    my $self = shift;
    my $array_ref = shift;
    my %p = @_;
    return if 0 == grep {defined $p{$_}} keys %p;
    delete $p{member};
    delete $p{_check_remote};
    if(wantarray){
        return grep {my $g = $_;(first {$p{$_} ne $g->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @$array_ref;
    }
    else{
        return first {my $g = $_;(first {$p{$_} ne $g->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @$array_ref;
    }
}
1;
