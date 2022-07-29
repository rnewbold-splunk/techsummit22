#!/bin/bash 

# Boot strap script for ITSI Labs
# Tech Summit '23

validate() {
	$SPLUNK_HOME/bin/splunk status
	if [[ $? -ne 0 ]]; then
		return 6
	fi
        readarray -t sims < <(pgrep -f -a "(simdata|data-blaster)")
	if [[ ${#sims[@]} -lt 8 ]]; then
		printf "%s" ${sims[@]}
		return 6
	fi
}

setup() {
	# SLO cert location & workdir
	SLOHOME="$SPLUNK_HOME/etc/auth/slocert"
	mkdir -p $SLOHOME; cd $SLOHOME

	# get host details
	fqpublichostname=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname)
	fqprivatehostname=$(curl -s http://169.254.169.254/latest/meta-data/hostname) 
	publichostname=$(echo $fqpublichostname | awk -F"." '{print $1}')
	privatehostname=$(echo $fqprivatehostname | awk -F"." '{print $1}')
	if [[ -z fqpublichostname || -z fqprivatehostname ]];then
		printf "Error: Splunk Enterprise certificate generation. Failed to get instance host metadata\n"
	else
		printf "Public FQDN:  %s\nPublic host:  %s\nPrivate FQDN: %s\nPrivate host: %s" $fqpublichostname $publichostname $fqprivatehostname $privatehostname  > commonname.txt
	fi

	# correct server.conf
	sed -E -i "s/^serverName\s=.+/serverName = $fqpublichostname/" /opt/splunk/etc/system/local/server.conf 
	if [[ $? -ne 0 ]]; then
		printf "Update of server.conf failed\n"
	fi

	# SLO Cert creation
	country=US
	state=CA
	locality=CA
	organization="Splunk Inc"
	organizationalunit=PS
	email=admin@splunk.com

	$SPLUNK_HOME/bin/splunk cmd openssl genrsa -aes256 -out myCAPrivateKey.key -passout pass:Splunk£verything 2048
	$SPLUNK_HOME/bin/splunk cmd openssl req -new -key myCAPrivateKey.key -out myCACertificate.csr -passin pass:Splunk£verything -subj "/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$fqpublicname/emailAddress=$email"
	echo -e "# ssl-extensions-x509.cnf\n[v3_ca]\nbasicConstraints = CA:FALSE\nkeyUsage = digitalSignature, keyEncipherment\nsubjectAltName = DNS:$fqpublichostname" > ssl-extensions-x509.cnf
	$SPLUNK_HOME/bin/splunk cmd openssl x509 -req -in myCACertificate.csr -signkey myCAPrivateKey.key -extensions v3_ca -extfile ./ssl-extensions-x509.cnf -out myCACertificate.pem -days 3650 -passin pass:Splunk£verything
	$SPLUNK_HOME/bin/splunk cmd openssl genrsa -aes256 -out mySplunkWebPrivateKey.key -passout pass:Splunk£verything 2048
	$SPLUNK_HOME/bin/splunk cmd openssl rsa -in mySplunkWebPrivateKey.key -out mySplunkWebPrivateKey.key -passin pass:Splunk£verything
	$SPLUNK_HOME/bin/splunk cmd openssl rsa -in mySplunkWebPrivateKey.key -text >/dev/null 2>&1
	if [[ $? -ne 0 ]]; then
		printf "Error: Splunk Enterprise certificate generation. Failed to read certificate!\n"
		return 1
	fi

	$SPLUNK_HOME/bin/splunk cmd openssl req -new  -key mySplunkWebPrivateKey.key -out mySplunkWebCert.csr -subj "/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$fqpublicname/emailAddress=$email"
	$SPLUNK_HOME/bin/splunk cmd openssl x509 -req -in mySplunkWebCert.csr -CA myCACertificate.pem -extensions v3_ca -extfile ./ssl-extensions-x509.cnf -CAkey myCAPrivateKey.key -CAcreateserial -out mySplunkWebCert.pem -days 1095 -passin pass:Splunk£verything 
	cat mySplunkWebCert.pem myCACertificate.pem > mySplunkWebCertificate.pem
	cat mySplunkWebCertificate.pem mySplunkWebPrivateKey.key > SLOcert.pem
	if [[ -f ./SLOcert.pem ]]; then
		cp mySplunkWebPrivateKey.key SLOSplunkWebPrivate.key
		rm -rf $SLOHOME/my*.* $SLOHOME/ssl-extensions-x509.cnf
		chmod -R 700 $SLOHOME
	else
		printf "Error: Splunk Enterprise certificate generation. Final certificate file not found?\n"
		return 1
	fi
}

# main
if [[ -z $SPLUNK_HOME ]]; then
	SPLUNK_HOME=/opt/splunk
fi

# Check user
if [[ $USER != splunk ]]; then
        printf 'ERROR: Boot strap must be run as splunk but %s found\nsudo su - splunk and try again\n' $USER
        exit 1
fi

if [[ -z $1 ]]; then
	printf "ERROR: Required argument missing\n"
	exit 1
elif [[ $1 == validate ]]; then
	validate
	exit $?
elif [[ $1 == setup ]]; then
	setup
	exit $?
fi
