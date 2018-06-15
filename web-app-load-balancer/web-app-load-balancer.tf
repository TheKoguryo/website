/*
 * This example demonstrates round robin load balancing behavior by creating two instances, a configured
 * vcn and a load balancer. The public IP of the load balancer is outputted after a successful run, curl
 * this address to see the hostname change as different instances handle the request.
 *
 * NOTE: The https listener is included for completeness but should not be expected to work,
 * it uses dummy certs.
 */

variable "tenancy_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {}
variable "private_key_path" {}
variable "compartment_ocid" {}
variable "region" {}

variable "ssh_public_key" {}

variable "InstanceImageOCID" {
  type = "map"

  default = {
    // Oracle-provided image "Oracle-Linux-7.4-2017.12.18-0"
    // See https://docs.us-phoenix-1.oraclecloud.com/Content/Resources/Assets/OracleProvidedImageOCIDs.pdf
    us-phoenix-1 = "ocid1.image.oc1.phx.aaaaaaaasc56hnpnx7swoyd2fw5gyvbn3kcdmqc2guiiuvnztl2erth62xnq"

    us-ashburn-1   = "ocid1.image.oc1.iad.aaaaaaaaxrqeombwty6jyqgk3fraczdd63bv66xgfsqka4ktr7c57awr3p5a"
    eu-frankfurt-1 = "ocid1.image.oc1.eu-frankfurt-1.aaaaaaaayxmzu6n5hsntq4wlffpb4h6qh6z3uskpbm5v3v4egqlqvwicfbyq"
  }
}

provider "oci" {
  tenancy_ocid     = "${var.tenancy_ocid}"
  user_ocid        = "${var.user_ocid}"
  fingerprint      = "${var.fingerprint}"
  private_key_path = "${var.private_key_path}"
  region           = "${var.region}"
}

data "oci_identity_availability_domains" "ADs" {
  compartment_id = "${var.tenancy_ocid}"
}

/* Network */

resource "oci_core_virtual_network" "vcn1" {
  cidr_block     = "10.1.0.0/16"
  compartment_id = "${var.compartment_ocid}"
  display_name   = "vcn1"
  dns_label      = "vcn1"
}

#AD1
resource "oci_core_subnet" "subnet1" {
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[0],"name")}"
  cidr_block          = "10.1.20.0/24"
  display_name        = "subnet1"
  dns_label           = "subnet1"
  security_list_ids   = ["${oci_core_security_list.securitylist1.id}"]
  compartment_id      = "${var.compartment_ocid}"
  vcn_id              = "${oci_core_virtual_network.vcn1.id}"
  route_table_id      = "${oci_core_route_table.routetable1.id}"
  dhcp_options_id     = "${oci_core_virtual_network.vcn1.default_dhcp_options_id}"

  provisioner "local-exec" {
    command = "sleep 5"
  }
}

#AD2
resource "oci_core_subnet" "subnet2" {
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[1],"name")}"
  cidr_block          = "10.1.21.0/24"
  display_name        = "subnet2"
  dns_label           = "subnet2"
  security_list_ids   = ["${oci_core_security_list.securitylist1.id}"]
  compartment_id      = "${var.compartment_ocid}"
  vcn_id              = "${oci_core_virtual_network.vcn1.id}"
  route_table_id      = "${oci_core_route_table.routetable1.id}"
  dhcp_options_id     = "${oci_core_virtual_network.vcn1.default_dhcp_options_id}"

  provisioner "local-exec" {
    command = "sleep 5"
  }
}

resource "oci_core_internet_gateway" "internetgateway1" {
  compartment_id = "${var.compartment_ocid}"
  display_name   = "internetgateway1"
  vcn_id         = "${oci_core_virtual_network.vcn1.id}"
}

resource "oci_core_route_table" "routetable1" {
  compartment_id = "${var.compartment_ocid}"
  vcn_id         = "${oci_core_virtual_network.vcn1.id}"
  display_name   = "routetable1"

  route_rules {
    cidr_block        = "0.0.0.0/0"
    network_entity_id = "${oci_core_internet_gateway.internetgateway1.id}"
  }
}

resource "oci_core_security_list" "securitylist1" {
  display_name   = "public"
  compartment_id = "${oci_core_virtual_network.vcn1.compartment_id}"
  vcn_id         = "${oci_core_virtual_network.vcn1.id}"

  egress_security_rules = [{
    protocol    = "all"
    destination = "0.0.0.0/0"
  }]

  ingress_security_rules = [{
    tcp_options {
      "max" = 22
      "min" = 22
    }

    protocol = "6"
    source   = "0.0.0.0/0"
  },
    {
      tcp_options {
        "max" = 80
        "min" = 80
      }

      protocol = "6"
      source   = "0.0.0.0/0"
    },
    {
      tcp_options {
        "max" = 443
        "min" = 443
      }

      protocol = "6"
      source   = "0.0.0.0/0"
    },
    {
      icmp_options {
        "type" = 0
      }

      protocol = 1
      source   = "0.0.0.0/0"
    },
    {
      icmp_options {
        "type" = 3
        "code" = 4
      }

      protocol = 1
      source   = "0.0.0.0/0"
    },
    {
      icmp_options {
        "type" = 8
      }

      protocol = 1
      source   = "0.0.0.0/0"
    },
  ]
}

/* Instances */

#AD1
resource "oci_core_instance" "instance1" {
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[0],"name")}"
  compartment_id      = "${var.compartment_ocid}"
  display_name        = "be-instance1"
  image               = "${var.InstanceImageOCID[var.region]}"
  shape               = "VM.Standard1.2"
  subnet_id           = "${oci_core_subnet.subnet1.id}"
  hostname_label      = "be-instance1"

  metadata {
    ssh_authorized_keys = "${var.ssh_public_key}"
    user_data           = "${base64encode(var.user-data)}"
  }
}

#AD2
resource "oci_core_instance" "instance2" {
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[1],"name")}"
  compartment_id      = "${var.compartment_ocid}"
  display_name        = "be-instance2"
  image               = "${var.InstanceImageOCID[var.region]}"
  shape               = "VM.Standard1.2"
  subnet_id           = "${oci_core_subnet.subnet2.id}"
  hostname_label      = "be-instance2"

  metadata {
    ssh_authorized_keys = "${var.ssh_public_key}"
    user_data           = "${base64encode(var.user-data)}"
  }
}

variable "user-data" {
  default = <<EOF
#!/bin/bash -x
echo '################### webserver userdata begins #####################'
touch ~opc/userdata.`date +%s`.start

# echo '########## yum update all ###############'
# yum update -y

echo '########## basic webserver ##############'
yum install -y httpd mod_ssl openssl crypto-utils

systemctl enable  httpd.service
systemctl start  httpd.service

echo '<html><head></head><body><pre><code>' > /var/www/html/index.html

hostname >> /var/www/html/index.html

echo '' >> /var/www/html/index.html

cat /etc/os-release >> /var/www/html/index.html

echo '<p>' >> /var/www/html/index.html

ip addr show >> /var/www/html/index.html 2>&1

echo '<p>' >> /var/www/html/index.html

curl ifconfig.co >> /var/www/html/index.html

ifconfig -a | grep -ie flags -ie netmask >> /var/www/html/index.html

echo '<p>' >> /var/www/html/index.html

curl ifconfig.co >> /var/www/html/index.html

echo '</code></pre></body></html>' >> /var/www/html/index.html

mkdir -p /var/www/html/example/video/123

curl http://169.254.169.254/opc/v1/vnics/ >> /var/www/html/example/video/123/index.html

firewall-offline-cmd --add-service=http
firewall-offline-cmd --add-service=https
systemctl enable  firewalld
systemctl restart  firewalld

touch ~opc/userdata.`date +%s`.finish
echo '################### webserver userdata ends #######################'
EOF
}

/* Load Balancer */

resource "oci_load_balancer" "lb1" {
  shape          = "100Mbps"
  compartment_id = "${var.compartment_ocid}"

  subnet_ids = [
    "${oci_core_subnet.subnet1.id}",
    "${oci_core_subnet.subnet2.id}",
  ]

  display_name = "lb1"
}

resource "oci_load_balancer_backendset" "lb-bes1" {
  name             = "lb-bes1"
  load_balancer_id = "${oci_load_balancer.lb1.id}"
  policy           = "ROUND_ROBIN"

  health_checker {
    port                = "80"
    protocol            = "HTTP"
    response_body_regex = ".*"
    url_path            = "/"
  }
}

/* *****************************************************************************
Quick self signed key procedure

1
openssl genrsa 2048 > privatekey.pem

2
openssl req -new -key privatekey.pem -out csr.pem

3 
openssl x509 -req -days 999 -in csr.pem -signkey privatekey.pem -out server.crt


public_certificate / CERTIFICATE / server.crt / -----BEGIN CERTIFICATE-----
ca_certificate / CA CERTIFICATE / csr.pem / -----BEGIN CERTIFICATE REQUEST-----
private_key / PRIVATE KEY / privatekey.pem / -----BEGIN RSA PRIVATE KEY-----

terraform - needs "\n" after BEGIN----\n and before \n-----END
*******************************************************************************
*/

resource "oci_load_balancer_certificate" "lb-cert1" {
  load_balancer_id   = "${oci_load_balancer.lb1.id}"
  ca_certificate     = "-----BEGIN CERTIFICATE REQUEST-----\nMIICyjCCAbICAQAwgYQxCzAJBgNVBAYTAlVTMRMwEQYDVQQIDApDYWxpZm9ybmlhMRcwFQYDVQQHDA5SZWR3b29kIFNob3JlczEPMA0GA1UECgwGT3JhY2xlMRYwFAYDVQQDDA1vcmFjbGV2Y24uY29tMR4wHAYJKoZIhvcNAQkBFg9yb290QG9yYWNsZS5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDLTx/GVfFVc9U+ofd3zBRbYA4UrOoVN6RMaK5Yf4wCMbnsTwtTSwa6tz/8XadZxs8tF1B+hlf3zaznRBEGCBXH37SCeUjlwHEJ+TLSi8/ofP3cC2vV6/Z6F4624iJoKkVOZZj8OGrpyGftJmRqUFxDfktkW41vp1Gv8BkBSARcgfTqZdPIO4srUf2MALJ3cFZTNtmcs0FFDeJV1OXFI/UfSXkNcuB4P+fZ57AGxdqZpVkvIKHfMIQBVtvlqx5f9hokMUHruHQys2i12J79q7CihWzO24BeL9vxcUnZS8gQQBpvU6io6p5cpAhoORJoOtFcchwDhVwT7o5VCrMk6adXAgMBAAGgADANBgkqhkiG9w0BAQsFAAOCAQEAljH9fRfTkdwFrTH7h5xJ14uRDC6PVaM1eA96msdby+ZEJPquIuVgNLTmWy4dCwiQi+pU6RdHeNdKOvq4DbMDOa4b2g0pPJ/tb/7eSNuw0I0pJlHzgcuJXDJ5mHoVUxYvthwmoqO68Tzce6NXvGphYnkGmFu44CjMd60kiRfjVbVavIQQcJeBmYlmhJDLyoyRRbKT5fbfx4ldrWkeh0QI0c4OqUFsbMwp7LbRkidVgXRcSDiXfy6qIgHMOTsJuspQHczinGCcsYh0N7kfIlR1QEA2kQoqRwOsUbxiJrfKBy4G9BZ68slbVE3Nrb0Qwhow/mOn45hFUkMrWjMyW/BfSQ==\n-----END CERTIFICATE REQUEST-----"
  certificate_name   = "oraclevcn.com"
  private_key        = "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEAy08fxlXxVXPVPqH3d8wUW2AOFKzqFTekTGiuWH+MAjG57E8LU0sGurc//F2nWcbPLRdQfoZX982s50QRBggVx9+0gnlI5cBxCfky0ovP6Hz93Atr1ev2eheOtuIiaCpFTmWY/Dhq6chn7SZkalBcQ35LZFuNb6dRr/AZAUgEXIH06mXTyDuLK1H9jACyd3BWUzbZnLNBRQ3iVdTlxSP1H0l5DXLgeD/n2eewBsXamaVZLyCh3zCEAVbb5aseX/YaJDFB67h0MrNotdie/auwooVsztuAXi/b8XFJ2UvIEEAab1OoqOqeXKQIaDkSaDrRXHIcA4VcE+6OVQqzJOmnVwIDAQABAoIBABIykNuF0cYeShYDFU1pvOC45km/eGxRwKj+LazKLdP8c3HNWWwpKP8Ja/bAwzvr6ZtVnOTWTYVmqXVByGxLyPdM9LFA/d9irDuCTKQ/02ox1d8ePpa1OiiPdzyzXPUJ444y1dCtlBQ81eCKMS665qc75K+k6jH2Pf+LdBGDSrCk4FnSHPSwv3CahWOkdrI3jmZX4o2yolJxph8n44aeYUY4uZSAG5Hrv6m7X6/JKgrF1DseXj7IS9P4Cx3Ua/F3AR2KpDzIwE+/wR3XsZQztUSLpYmb1CR57WfaSz3q4yLLGDgDO4x8XNxZvdJYiSFQXOSNBhocBCOHxupcz7HSASECgYEA5Wd6YEImCTxwVsQJdazG1pWT7eXrz8/5TKQAGd8VkyvCbpK1LHzttsc3p6znfqpgFgo0WycKGoA4SXpWzUX5K3ZKS+yN2kyxvB+fuSK0mdggtmI5H5qgaBDN0At0036vcIdbu4PPF+XSNoPQ1XGQfdjKCANXO37LkwkuGV93URkCgYEA4uEqLHDMy6DD4293s+ca8IOrFhB0LLgHB//y4RYQ1Mn7IrDIWTTevCMNMEahGB5op71hLOu14M7k1Kwc/VCsQgKqDBq0X2Wyu530fle5JDiXa5F+xwu9dKwx35D/fuzwoWQyE2MVAfAdv48dzxTMyznoBx7mBV7DYz5unz4Vme8CgYEAzQqlbf4R4zV7L4I+9kf83XWKaBuWnwNDz4XSdU1ZClcVjSFiACaVjkYX763yp9t+0JREYajONguew8YuaYF+iaNMGvqPe6wLPJuDdsWXaN6ttnaqmh3p+7nxS1/CBvt3sfu6OStB4hlPv9wnv2+m92Tahzj9MjdNm9mbs6AJlJkCgYAAuFY57eG4g7obbq8ikwky2jggycyUl8Dt9ZH/xOIoyrtRUN5R6ikKz9Gq5Y59VRtf7OnyCo15OS7gvesZorfpPbjscOlBpED893NfM0gTJVrVrJCKcS8Yv7Mo0nz9GiNpX7gI97eJWgm+IeYmUhqUSorB+wcf3T0hg4E2YCwRYQKBgQDCET3f6W7HRNNCOc6d+S5y21IPCVYJJj3VMGWGHdnRMGqJEGWJTH4PUws8W7unMp3uE/XCBXu1JBjtLXObDaX6UGHe+u5ZBCgyn9mlwc/2pqde5yfnQWX00klHszU/8Q8kyYxEuxJCAVZ8BqiJb+tGOcweGohuLyH2UyUgYSsF8A==\n-----END RSA PRIVATE KEY-----"
  public_certificate = "-----BEGIN CERTIFICATE-----\nMIIDhjCCAm4CCQDe1xnxVAAUrDANBgkqhkiG9w0BAQsFADCBhDELMAkGA1UEBhMCVVMxEzARBgNVBAgMCkNhbGlmb3JuaWExFzAVBgNVBAcMDlJlZHdvb2QgU2hvcmVzMQ8wDQYDVQQKDAZPcmFjbGUxFjAUBgNVBAMMDW9yYWNsZXZjbi5jb20xHjAcBgkqhkiG9w0BCQEWD3Jvb3RAb3JhY2xlLmNvbTAeFw0xODAzMjkwMDIxMTJaFw0yMDEyMjIwMDIxMTJaMIGEMQswCQYDVQQGEwJVUzETMBEGA1UECAwKQ2FsaWZvcm5pYTEXMBUGA1UEBwwOUmVkd29vZCBTaG9yZXMxDzANBgNVBAoMBk9yYWNsZTEWMBQGA1UEAwwNb3JhY2xldmNuLmNvbTEeMBwGCSqGSIb3DQEJARYPcm9vdEBvcmFjbGUuY29tMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAy08fxlXxVXPVPqH3d8wUW2AOFKzqFTekTGiuWH+MAjG57E8LU0sGurc//F2nWcbPLRdQfoZX982s50QRBggVx9+0gnlI5cBxCfky0ovP6Hz93Atr1ev2eheOtuIiaCpFTmWY/Dhq6chn7SZkalBcQ35LZFuNb6dRr/AZAUgEXIH06mXTyDuLK1H9jACyd3BWUzbZnLNBRQ3iVdTlxSP1H0l5DXLgeD/n2eewBsXamaVZLyCh3zCEAVbb5aseX/YaJDFB67h0MrNotdie/auwooVsztuAXi/b8XFJ2UvIEEAab1OoqOqeXKQIaDkSaDrRXHIcA4VcE+6OVQqzJOmnVwIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQA5ATiiBE9wuAc1IKDPTChAXsu3Z/hQ7p7Yy9N0+EVlY6gjUgBgCYw7y6Qu6p+SxJCXVAiBW05jAJ5hwHfijnCdauXIAWDjLsJvT/+Sa74n/3DYYt0mGmd9MdMnHL3120airyeeFwloMUk8lhyQKPDtXtvaY9ZDWbzwBZEQCFJRbhHrSTH1iaRz04rrYc1qjt6bHIz+bbfimlmdiOTWAMMbEi0ONeptPFXbNQ/d4oZWudlDNszJacG1Ez1sysJwxpGfg6UhEVvZqzWzsL3VXvbNdlbh9QouaLYWkylQRBbEcwGqg8oTSjAKAIU92J2jn60Z/joVgfneVzs6VNZiWcld\n-----END CERTIFICATE-----"
}

resource "oci_load_balancer_path_route_set" "test_path_route_set" {
  #Required
  load_balancer_id = "${oci_load_balancer.lb1.id}"
  name             = "pr-set1"

  path_routes {
    #Required
    backend_set_name = "${oci_load_balancer_backendset.lb-bes1.name}"
    path             = "/example/video/123"

    path_match_type {
      #Required
      match_type = "EXACT_MATCH"
    }
  }
}

resource "oci_load_balancer_listener" "lb-listener1" {
  load_balancer_id         = "${oci_load_balancer.lb1.id}"
  name                     = "http"
  default_backend_set_name = "${oci_load_balancer_backendset.lb-bes1.id}"
  port                     = 80
  protocol                 = "HTTP"

  connection_configuration {
    idle_timeout_in_seconds = "2"
  }
}

resource "oci_load_balancer_listener" "lb-listener2" {
  load_balancer_id         = "${oci_load_balancer.lb1.id}"
  name                     = "https"
  default_backend_set_name = "${oci_load_balancer_backendset.lb-bes1.id}"
  port                     = 443
  protocol                 = "HTTP"

  ssl_configuration {
    certificate_name        = "${oci_load_balancer_certificate.lb-cert1.certificate_name}"
    verify_peer_certificate = false
  }
}

resource "oci_load_balancer_backend" "lb-be1" {
  load_balancer_id = "${oci_load_balancer.lb1.id}"
  backendset_name  = "${oci_load_balancer_backendset.lb-bes1.id}"
  ip_address       = "${oci_core_instance.instance1.private_ip}"
  port             = 80
  backup           = false
  drain            = false
  offline          = false
  weight           = 1
}

resource "oci_load_balancer_backend" "lb-be2" {
  load_balancer_id = "${oci_load_balancer.lb1.id}"
  backendset_name  = "${oci_load_balancer_backendset.lb-bes1.id}"
  ip_address       = "${oci_core_instance.instance2.private_ip}"
  port             = 80
  backup           = false
  drain            = false
  offline          = false
  weight           = 1
}

output "lb_public_ip" {
  value = ["${oci_load_balancer.lb1.ip_addresses}"]
}
