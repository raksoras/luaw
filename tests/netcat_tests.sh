SLEEP1=1
SLEEP2=1
SLEEP3=1

REQ1="GET /myapp/address/1860/Mento_Dr/Fremont/CA/94539 HTTP/1.1\r\nHost:localhost:7001\r\nAccept: */*\r\nContent-Length: 0\r\n\r\n"
REQ2="GET /myapp/address/396/Ano_Nuevo_Ave/Sunnyvale/CA/94860 HTTP/1.1\r\nHost:localhost:7001\r\nAccept: */*\r\nContent-Length: 0\r\n\r\n"
REQ3="GET /myapp/address/100/Winchester_Cir/Los_Gatos/CA/94032 HTTP/1.1\r\nHost:localhost:7001\r\nAccept: */*\r\nContent-Length: 0\r\n\r\n"


if [ $1 -eq 1 ]
then
	echo -ne $REQ1 | nc localhost 7001
    echo "Tested single connection"
fi

if [ $1 -eq 2 ]
then
	(echo -ne $REQ1; sleep $SLEEP1; echo -ne $REQ2; sleep $SLEEP2; echo -ne $REQ3; sleep $SLEEP3) | nc localhost 7001
    echo "Tested persistent connections"
fi

if [ $1 -eq 3 ]
then
	(echo -ne $REQ1; echo -ne $REQ2; echo -ne $REQ3) | nc localhost 7001
    echo "Tested pipelined connections"
fi
