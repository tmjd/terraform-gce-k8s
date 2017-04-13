# See https://cloud.google.com/compute/docs/load-balancing/network/example

provider "google" {
  region      = "${var.region}"
  project     = "${var.project_name}"
  credentials = "${file("${var.credentials_file_path}")}"
}

resource "google_compute_network" "calico-net" {
  name = "calico-network"
  auto_create_subnetworks = "false"
}

resource "google_compute_subnetwork" "calico-subnet" {
  name          = "calico-subnet"
  ip_cidr_range = "10.128.0.0/16"
  network       = "${google_compute_network.calico-net.self_link}"
  region        = "${var.region}"
}

data "template_file" "master_init" {
  template = "${file("master-config.yaml")}"

  vars {
    ssh_authorized_key = "${file("${var.public_key_path}")}"
  }
}

resource "google_compute_instance" "calico-master" {
  count = 1

  name         = "calico-master-${count.index}"
  machine_type = "n1-standard-4"
  zone         = "${var.region_zone}"

  tags = ["calico","master"]

  disk {
    image = "ubuntu-os-cloud/ubuntu-1610-yakkety-v20170330"
    # Find images by:
    #   gcloud config set project dummy-xxxxx
    #   gcloud auth login
    #   gcloud compute images list
  }

  network_interface {
    subnetwork = "${google_compute_subnetwork.calico-subnet.name}"

    access_config {
      # Ephemeral
    }
  }

  metadata {
    #ssh-keys = "root:${file("${var.public_key_path}")}"
    user-data = "${data.template_file.master_init.rendered}"
  }

  service_account {
    scopes = ["https://www.googleapis.com/auth/compute.readonly"]
  }

  provisioner "file" {
    source = "install.sh"
    destination = "/tmp/install.sh"

    connection {
      type = "ssh"
      user = "ubuntu"
    }
  }

  provisioner "remote-exec" {
    connection {
      type = "ssh"
      user = "ubuntu"
    }

    inline = [
      "chmod +x /tmp/install.sh",
      "sudo /tmp/install.sh",
      "sudo kubeadm init --token 2a9c0e.31e11f6489468e5e",
      "mkdir /home/ubuntu/.kube",
      "sudo cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config",
      "sudo chown -R ubuntu /home/ubuntu/.kube"
    ]
  }
}

data "template_file" "node_init" {
  template = "${file("node-config.yaml")}"

  vars {
    master_ip = "${google_compute_instance.calico-master.network_interface.0.address}"
    ssh_authorized_key = "${file("${var.public_key_path}")}"
  }
}

resource "google_compute_instance" "calico" {
  count = 2

  name         = "calico-${count.index}"
  machine_type = "n1-standard-1"
  zone         = "${var.region_zone}"
  tags         = ["www-node"]

  disk {
    image = "ubuntu-os-cloud/ubuntu-1610-yakkety-v20170330"
  }

  network_interface {
    subnetwork = "${google_compute_subnetwork.calico-subnet.name}"

    access_config {
      # Ephemeral
    }
  }

  metadata {
    user-data = "${data.template_file.node_init.rendered}"
  }

  service_account {
    scopes = ["https://www.googleapis.com/auth/compute.readonly"]
  }

  provisioner "file" {
    source = "install.sh"
    destination = "/tmp/install.sh"

    connection {
      type = "ssh"
      user = "ubuntu"
    }
  }

  provisioner "remote-exec" {
    connection {
      type = "ssh"
      user = "ubuntu"
    }

    inline = [
      "chmod +x /tmp/install.sh",
      "sudo /tmp/install.sh",
      "sudo kubeadm join --token 2a9c0e.31e11f6489468e5e ${google_compute_instance.calico-master.network_interface.0.address}:6443",
    ]
  }
}

resource "google_compute_firewall" "all-source" {
  name = "all-source"
  network = "${google_compute_network.calico-net.name}"

  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports = [ "22", "3389" ]
  }
}

resource "google_compute_firewall" "internal-rules" {
  name = "internal-rules"
  network = "${google_compute_network.calico-net.name}"

  source_ranges = ["${google_compute_subnetwork.calico-subnet.ip_cidr_range}"]

  allow {
    protocol = "4"
  }

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports = [ "0-65535" ]
  }

  allow {
    protocol = "udp"
    ports = [ "0-65535" ]
  }
}
