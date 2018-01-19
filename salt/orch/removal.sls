# TODO: get the "target" from the ... pillar?

{%- set masters = salt.saltutil.runner('mine.get', tgt='G@roles:kube-master', fun='network.interfaces', tgt_type='compound').keys() %}
{%- set etcd_members = salt.saltutil.runner('mine.get', tgt='G@caasp_etcd_member', fun='network.interfaces', tgt_type='compound').keys() %}

# Generic Updates
sync_pillar:
  salt.runner:
    - name: saltutil.sync_pillar

update_pillar:
  salt.function:
    - tgt: '*'
    - name: saltutil.refresh_pillar
    - require:
      - salt: generate_sa_key

update_grains:
  salt.function:
    - tgt: '*'
    - name: saltutil.refresh_grains

update_mine:
  salt.function:
    - tgt: '*'
    - name: mine.update
    - require:
       - salt: update_pillar
       - salt: update_grains

update_modules:
  salt.function:
    - name: saltutil.sync_modules
    - tgt: '*'
    - kwarg:
        refresh: True
    - require:
      - salt: update_mine

{% if target in etcd_members %}
  # if the node is a member of the etcd cluster:
  # we must choose a etcd proxy and promote it to an etcd master
  {% set etcd_proxies = salt.saltutil.runner('mine.get', tgt='not G@caasp_etcd_member', fun='network.interfaces', tgt_type='compound').keys() %}
  {% if etcd_proxies|length > 0 %}
    {% set some_etcd_proxy = etcd_proxies[0] %}

    # promote some other proxy to be a full member of the etcd cluster
    # WARNING: we should do a consistency check in Velum...
    #          if no proxy is available for promotion and:
    #          * num_members >= 3  ->  we should show a "are you sure??" message.
    #          * num_members == 1  ->  we should just not allow it
    #
etc_proxy_promote:
  salt.state:
    - tgt: '{{ some_etcd_proxy }}'
    - sls:
      - etcd.remove-pre-stop_services
    - require:
      - salt: update_modules
  {% endif %}

  # remove the etcd master running in {{ target }}
etc_remove_master:
  salt.state:
    - tgt: '{{ target }}'
    - sls:
      - etcd.remove-pre-stop_services
    - require:
      {% if etcd_proxies|length > 0 %}
      - salt: etc_proxy_promote
      {% else %}
      - salt: update_modules
      {% endif %}

  # and we don't have to do anything special when removing a 'proxy' from the cluster:
  # just stop the services...

{% endif %}

# TODO: if {{ target }} is a k8s master, we should promote a worker... but this is
#       too hard to do right now

update_grains:
  salt.function:
    - tgt: '*'
    - name: saltutil.refresh_grains
    {% if target in etcd_members %}
    - require:
      - salt: etc_remove_master
    {% endif %}

stop_services:
  salt.state:
    - tgt: '{{ target }}'
    - sls:
      - container-feeder.stop
      {% if target in masters %}
      - kube-apiserver.stop
      - kube-controller-manager.stop
      - kube-scheduler.stop
      {% else %}
      - kubelet.stop
      - kube-proxy.stop
      {% endif %}
      - docker.stop
      - etcd.stop
    - require:
      - salt: update_grains

# revoke certificates
# TODO

# revoke Salt keys
# TODO

# remove any other configuration in the machines
# TODO: all the files in /etc/kubernetes/*, /var/lib/kubernetes/* ??
remove-pre-reboot:
  salt.state:
    - tgt: '{{ some_etcd_proxy }}'
    - sls:
      - container-feeder.remove-pre-reboot
      {% if target in masters %}
      - kube-apiserver.remove-pre-reboot
      - kube-controller-manager.remove-pre-reboot
      - kube-scheduler.remove-pre-reboot
      {% else %}
      - kubelet.remove-pre-reboot
      - kube-proxy.remove-pre-reboot
      {% endif %}
      - docker.remove-pre-reboot
      - cni.remove-pre-reboot
      - etcd.remove-pre-reboot
    - require:
      - salt: stop_services

# reboot the node
reboot-node:
  salt.function:
    - tgt: {{ target }}
    - name: cmd.run
    - arg:
      - sleep 15; systemctl reboot
    - kwarg:
        bg: True
    - require:
      - salt: remove-pre-reboot

# we don't need to wait for the node to reboot: just forget about it...
