#!/bin/bash

# This script is used to run vagrant based tests on Travis.
# This script is started via sudo from .travis.yml

set -e
set -x

VAGRANT_VERSION=2.2.14
FEDORA_VERSION=33
FEDORA_BOX_VERSION=33.20201019.0

setup() {
	if [ -n "$TRAVIS" ]; then
		# Load the kvm modules for vagrant to use qemu
		modprobe kvm kvm_intel
	fi

	# Tar up the git checkout to have vagrant rsync it to the VM
	tar cf criu.tar ../../../criu
	# Cirrus has problems with the following certificate.
	wget --no-check-certificate https://releases.hashicorp.com/vagrant/${VAGRANT_VERSION}/vagrant_${VAGRANT_VERSION}_"$(uname -m)".deb -O /tmp/vagrant.deb && \
		dpkg -i /tmp/vagrant.deb

	./apt-install libvirt-clients libvirt-daemon-system libvirt-dev qemu-utils qemu \
		ruby build-essential libxml2-dev qemu-kvm rsync ebtables dnsmasq-base \
		openssh-client
	systemctl restart libvirtd
	vagrant plugin install vagrant-libvirt
	vagrant init fedora/${FEDORA_VERSION}-cloud-base --box-version ${FEDORA_BOX_VERSION}
	# The default libvirt Vagrant VM uses 512MB.
	# Travis VMs should have around 7.5GB.
	# Increasing it to 4GB should work.
	sed -i Vagrantfile -e 's,^end$,  config.vm.provider :libvirt do |libvirt|'"\n"'    libvirt.memory = 4096;end'"\n"'end,g'
	vagrant up --provider=libvirt --no-tty
	mkdir -p /root/.ssh
	vagrant ssh-config >> /root/.ssh/config
	ssh default sudo dnf upgrade -y
	ssh default sudo dnf install -y gcc git gnutls-devel nftables-devel libaio-devel \
		libasan libcap-devel libnet-devel libnl3-devel make protobuf-c-devel \
		protobuf-devel python3-flake8 python3-future python3-protobuf \
		python3-junit_xml rubygem-asciidoctor iptables libselinux-devel libbpf-devel
	# Disable sssd to avoid zdtm test failures in pty04 due to sssd socket
	ssh default sudo systemctl mask sssd
	ssh default cat /proc/cmdline
}

fedora-no-vdso() {
	ssh default sudo grubby --update-kernel ALL --args="vdso=0"
	vagrant reload
	ssh default cat /proc/cmdline
	ssh default 'cd /vagrant; tar xf criu.tar; cd criu; make -j 4'
	# BPF tests are failing see: https://github.com/checkpoint-restore/criu/issues/1354
	# Needs to be fixed, skip for now
	ssh default 'cd /vagrant/criu/test; sudo ./zdtm.py run -a --keep-going -x zdtm/static/bpf_hash -x zdtm/static/bpf_array'
}

fedora-non-root() {
	# Need a reboot to activate the latest Fedora kernel with CAP_CHECKPOINT_RESTORE
	vagrant reload
	ssh default uname -a
	ssh default 'cd /vagrant; tar xf criu.tar; cd criu; make -j 4'
	# Setting the capability should be the only line needed to run as root
	ssh default 'sudo setcap cap_checkpoint_restore+eip /vagrant/criu/criu/criu'
	# Run it once as non-root
	ssh default 'cd /vagrant/criu; criu/criu check --unprivileged; ./test/zdtm.py run -t zdtm/static/env00 -t zdtm/static/pthread00 -f h'
	# Run it as root with '--rootless'
	ssh default 'cd /vagrant/criu; sudo ./test/zdtm.py run -t zdtm/static/env00 -t zdtm/static/pthread00 -f h; sudo chmod 777 test/dump/zdtm/static/{env00,pthread00}; sudo ./test/zdtm.py run -t zdtm/static/env00 -t zdtm/static/pthread00 -f h --rootless'
}

$1
