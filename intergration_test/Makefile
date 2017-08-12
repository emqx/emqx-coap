
.PHONY: clean, clean_result, start_broker  stop_broker  case1 case2 case3

RELX_CONF    = emq-relx/relx.config
LIBCOAP_GIT  = libcoap/README.md




all:  clean_result $(RELX_CONF) $(LIBCOAP_GIT) start_broker clean_result case1  case2  case3 case4 stop_broker
	@echo "  "
	@echo "  test complete"
	@echo "  "
	
clean_result:
	-rm -f case*.txt

	
start_broker:
	-rm -f emq-relx/_rel/emqttd/log/*
	-emq-relx/_rel/emqttd/bin/emqttd stop
	sleep 1
	emq-relx/_rel/emqttd/bin/emqttd start
	sleep 1
	emq-relx/_rel/emqttd/bin/emqttd_ctl plugins load emq_coap


stop_broker:
	-emq-relx/_rel/emqttd/bin/emqttd stop
	

case1:
	libcoap/examples/coap-client -m get -s 5  "coap://127.0.0.1/mqtt/topic1?c=client1&u=tom&p=secret" > case1_output.txt &
	sleep 1
	libcoap/examples/coap-client -m put -e w123G45 "coap://127.0.0.1/mqtt/topic1?c=client2&u=mike&p=pw12"
	sleep 6
	python check_result.py  case1  case1_output.txt==w123G45
	
case2:
	# subscribe to topic="x/y"
	libcoap/examples/coap-client -m get -s 5  "coap://127.0.0.1/mqtt/x%2Fy?c=client3&u=tom&p=secret" > case2_output1.txt &
	# subscribe to topic="+/z"
	libcoap/examples/coap-client -m get -s 5  "coap://127.0.0.1/mqtt/%2B%2Fz?c=client4&u=mike&p=pw12" > case2_output2.txt &
	sleep 1
	# publish to topic="x/y"
	libcoap/examples/coap-client -m put -e big9wolf "coap://127.0.0.1/mqtt/x%2Fy?c=client5&u=sun&p=pw3"
	# publish to topic="p/z"
	libcoap/examples/coap-client -m put -e black2ant "coap://127.0.0.1/mqtt/p%2Fz?c=client5&u=sun&p=pw3"
	sleep 6
	python check_result.py case2 case2_output1.txt==big9wolf  case2_output1.txt!=black2ant  case2_output2.txt!=big9wolf  case2_output2.txt==black2ant

case3:
	libcoap/examples/coap-client -m get -T tk12 -s 5  "coap://127.0.0.1/mqtt/a%2Fb?c=client3&u=tom&p=secret" > case3_output1.txt &
	libcoap/examples/coap-client -m get -T tk34 -s 5  "coap://127.0.0.1/mqtt/c%2Fd?c=client3&u=tom&p=secret" > case3_output2.txt &
	sleep 1
	libcoap/examples/coap-client -m put -e big9wolf "coap://127.0.0.1/mqtt/c%2Fd?c=client5&u=sun&p=pw3"
	libcoap/examples/coap-client -m put -e black2ant "coap://127.0.0.1/mqtt/a%2Fb?c=client5&u=sun&p=pw3"
	sleep 6
	python check_result.py case3 case3_output1.txt==black2ant  case3_output2.txt==big9wolf  case3_output2.txt!=black2ant
	


case4:
	# reload emq_coap, does it work as expected?
	sleep 1
	emq-relx/_rel/emqttd/bin/emqttd_ctl plugins unload emq_coap
	sleep 1
	emq-relx/_rel/emqttd/bin/emqttd_ctl plugins load emq_coap
	sleep 1
	libcoap/examples/coap-client -m get -s 5  "coap://127.0.0.1/mqtt/topic1?c=client1&u=tom&p=secret" > case4_output.txt &
	sleep 1
	libcoap/examples/coap-client -m put -e w6J3G45 "coap://127.0.0.1/mqtt/topic1?c=client2&u=mike&p=pw12"
	sleep 6
	python check_result.py  case4  case4_output.txt==w6J3G45



	
$(RELX_CONF):
	git clone https://github.com/emqtt/emq-relx.git
	git clone https://github.com/emqtt/emq-coap.git
	@echo "update emq-coap with this development code"
	mv emq-coap  emq_coap
	-rm -rf emq_coap/etc
	-rm -rf emq_coap/include
	-rm -rf emq_coap/priv
	-rm -rf emq_coap/src
	-rm -rf emq_coap/Makefile
	cp -rf ../etc      emq_coap/
	cp -rf ../include  emq_coap/
	cp -rf ../priv     emq_coap/
	cp -rf ../src      emq_coap/
	cp -rf ../Makefile emq_coap/Makefile
	-mkdir emq-relx/deps
	mv emq_coap  emq-relx/deps/
	@echo "start building ..."
	make -C emq-relx -f Makefile
	

coap:  $(LIBCOAP_GIT)
	@echo "make coap"
	
$(LIBCOAP_GIT):
	git clone -b v4.1.2 http://github.com/obgm/libcoap
	cd libcoap && ./autogen.sh && ./configure --enable-documentation=no --enable-tests=no 
	make -C libcoap -f Makefile
	
r: rebuild_emq
	# r short for rebuild_emq
	@echo " rebuild complete "
	
	
rebuild_emq:
	-emq-relx/_rel/emqttd/bin/emqttd stop
	-rm -rf emq-relx/deps/emq_coap/etc
	-rm -rf emq-relx/deps/emq_coap/include
	-rm -rf emq-relx/deps/emq_coap/priv
	-rm -rf emq-relx/deps/emq_coap/src
	-rm -rf emq-relx/deps/emq_coap/Makefile
	cp -rf ../etc      emq-relx/deps/emq_coap/
	cp -rf ../include  emq-relx/deps/emq_coap/
	cp -rf ../priv     emq-relx/deps/emq_coap/
	cp -rf ../src      emq-relx/deps/emq_coap/
	cp -rf ../Makefile emq-relx/deps/emq_coap/Makefile
	make -C emq-relx -f Makefile
	
	
clean: clean_result
	-rm -f client/*.exe
	-rm -f client/*.o
	-rm -rf emq-relx
	-rm -rf libcoap
	
	
	
lazy: clean_result start_broker case2  stop_broker
	# custom your command here
	@echo "you are so lazy"
	
	
	