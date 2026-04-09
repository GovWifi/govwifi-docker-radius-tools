eapol_test -a $(echo $RADIUS_SERVER_IP) -c /capacity_tests/eap_tls_missmatch.conf -s $(echo $RADIUS_SECRET)
