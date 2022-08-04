#!/bin/bash 

# Description: Boot strap script for core servers, Splunk O11y Labs, Tech Summit '22
# Author: rnewbold@splunk.com

slo_cert() {
	# SLO cert location & workdir
	SLOHOME="$SPLUNK_HOME/etc/auth/slocert"
	mkdir -p $SLOHOME; cd $SLOHOME

	# get host public details if AWS
	id ec2-user >/dev/null 2>&1
	if [[ $? -eq 0 ]]; then	
		fqpublichostname=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname)
	else
		while [[ -z $fqpublichostname ]]; do
			read -p "Unable to confirm public DNS name for this instance - please enter public FQDN:\n" fqpublichostname
		done
	fi
	publichostname=$(echo $fqpublichostname | awk -F"." '{print $1}')
	printf "Public FQDN:  %s\nPublic host:  %s\n" $fqpublichostname $publichostname > commonname.txt

	# SLO Cert creation
	country=US
	state=CA
	locality=CA
	organization="Splunk Inc"
	organizationalunit=EDU
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
	printf "example SLO certificate files created successfully\n" 	
}

# main
if [[ -z $SPLUNK_HOME ]]; then
	if [[ -f /opt/splunk/bin/splunk ]]; then
		SPLUNK_HOME=/opt/splunk
	else
		printf "ERROR: unable to confirm SPLUNK_HOME, aborting\nTo fix update $SPLUNK_HOME and export\n"
	fi
fi

# Check user
SPLUNKUSER=$(ls -l $SPLUNK_HOME/bin/splunk |  awk 'NR==1 {print $3}')
if [[ $USER != $SPLUNKUSER ]]; then
	printf 'ERROR: Boot strap must be run as SPLUNK user (%s) but active user '%s' found. Change user to %s and try again\n' $SPLUNKUSER $USER $SPLUNKUSER
        exit 1
fi

if [[ -z $1 ]]; then
	printf "ERROR: Required argument missing\n"
	exit 1
elif [[ $1 == setup ]]; then
	slo_cert
fi
