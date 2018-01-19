{% from '_macros/etcdctl.jinja' import etcdctl with context %}
{% from '_macros/network.jinja' import get_primary_ip, get_primary_ips_for with context %}

{% set this_id = grains['id'] %}
{% set this_ip = get_primary_ip() %}
{% set endpoints_ips = get_primary_ips_for('G@caasp_etcd_member') %}

{% set endpoints_urls = [] %}
{% for ip in endpoints_ips %}
   {% do endpoints_urls.append("https://" + ip + ":2379") %}
{% endfor %}

{% if salt['grains.get']('caasp_etcd_member', False) %}
  # this is a member of the etcd cluster: remove it from the cluster

etcd-remove-{{ this_id }}:
  caasp_etcd.run:
    name:
      etcdctl member remove {{ this_id }}
    env:
      ETCDCTL_ENDPOINT: {{ endpoints_urls|joint(',') }}
      ETCDCTL_CACERT:   {{ pillar['ssl']['ca_file'] }}
      ETCDCTL_CERT:     {{ pillar['ssl']['crt_file'] }}
      ETCDCTL_KEY:      {{ pillar['ssl']['key_file'] }}

{% else %}
  # if this is a proxy, so this state must have
  # been invoked for promoting this node to be a full member...

  {% set some_etcd_master_id = salt['mine.get']('caasp_etcd_member', 'network.interfaces', expr_form='grain').keys()[0] %}
  {% set some_etcd_master_ip = get_primary_ip(host=some_etcd_master_id) %}

etcd-promote-{{ this_id }}:
  caasp_etcd.run:
    name:
      etcdctl member add {{ this_id }} "http://{{ ip }}:2380"
    env:
      ETCDCTL_ENDPOINT: {{ endpoints_urls|joint(',') }}
      ETCDCTL_CACERT:   {{ pillar['ssl']['ca_file'] }}
      ETCDCTL_CERT:     {{ pillar['ssl']['crt_file'] }}
      ETCDCTL_KEY:      {{ pillar['ssl']['key_file'] }}

{% endif %}
