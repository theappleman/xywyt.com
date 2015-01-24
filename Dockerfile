FROM debian:7.7

MAINTAINER Daniel Cordero <docker@xxoo.ws>

RUN apt-get update
RUN apt-get upgrade -y

RUN apt-get install -y curl patch perl make liblist-allutils-perl libwww-perl libhtml-parser-perl libdigest-sha-perl libsocket-perl gcc



ADD . /app

RUN curl -skL cpanmin.us | perl - $(awk '/^use/{print$2}' /app/xywyt.pl | tr -d ';' | tac)
WORKDIR /usr/local/share/perl/5.14.2/
RUN patch -p3 /app/NOA-ATR.patch
WORKDIR /app

EXPOSE 8080
#CMD []
#ENTRYPOINT ["/usr/bin/hypnotoad", "-f"]

