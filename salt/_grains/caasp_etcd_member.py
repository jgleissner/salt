import logging
import os
import re
import subprocess

import salt.log

log = logging.getLogger(__name__)

# file where etcdctl env vars are set
ETCDCTL_ENV_VARS = '/etc/sysconfig/etcdctl'

# file where etcd env vars are set
ETCD_ENV_VARS = '/etc/sysconfig/etcd'

# a regex for matching URLs
URL_REGEX = 'http[s]?://(?:[a-zA-Z]|[0-9]|[$-_@.&+]|[!*\(\),]|(?:%[0-9a-fA-F][0-9a-fA-F]))+'


def __virtual__():
    if not os.path.exists(ETCDCTL_ENV_VARS):
        log.debug('caasp_etcd_member: {} does not exist yet'.format(
            ETCDCTL_ENV_VARS))
        return False
    else:
        return 'caasp_etcd_member'


# return a list of URLs where etcd peers are listening
def _get_etcdctl_peers_urls():
    res = set()

    cmd = "set -a ; source {} ; etcdctl member list".format(ETCDCTL_ENV_VARS)
    log.debug('caasp_etcd_member: getting members: {}'.format(cmd))
    try:
        out = subprocess.check_output([cmd], shell=True).strip(" \n\t")
        log.debug(
            'caasp_etcd_member: getting members: ... output: {}'.format(out))
    except subprocess.CalledProcessError, e:
        log.error(
            'caasp_etcd_member: getting members: could not run etcdctl: {}'.format(e))
        return res

    # parse all the peers URLs in the output
    # lines will look like this:
    #
    # 822729eac155a8d9: name=72f495ee631f4490a82b32d76f258b21 \
    #   peerURLs=https://72f495ee631f4490a82b32d76f258b21.infra.caasp.local:2380 \
    #   clientURLs=https://72f495ee631f4490a82b32d76f258b21.infra.caasp.local:2379 \
    #   isLeader=true
    #
    for peerStr in re.findall('peerURLs={}'.format(URL_REGEX), out):
        try:
            peerURL = peerStr.split('=')[1]
        except Exception, e:
            log.error(
                'caasp_etcd_member: could not parse {}: {}'.format(peerStr, e))
        else:
            log.debug(
                'caasp_etcd_member: getting members: ... parsed: {}'.format(peerURL))
            res.add(peerURL)

    return res


# get the local peer URL (ie, 'https://72f495ee631f4490a82b32d76f258b21.infra.caasp.local:2380')
def _get_local_peer_url():
    cmd = "set -a ; source {} ; echo $ETCD_INITIAL_ADVERTISE_PEER_URLS".format(
        ETCD_ENV_VARS)
    log.debug('caasp_etcd_member: getting local peer name: {}'.format(cmd))
    try:
        out = subprocess.check_output([cmd], shell=True).strip(" \n\t")
        log.debug(
            'caasp_etcd_member: getting local peer name: ... output: {}'.format(out))
    except subprocess.CalledProcessError, e:
        log.error(
            'caasp_etcd_member: getting local peer name: could not run etcdctl: {}'.format(e))
        raise

    log.debug('etcd local peer URL: {}'.format(out))
    return out


def caasp_etcd_member():
    grains = {}
    try:
        peer_urls = _get_etcdctl_peers_urls()
        if len(peer_urls) > 0:
            if _get_local_peer_url() in peer_urls:
                log.debug(
                    'caasp_etcd_member: the local node IS a member of the cluster')
                grains['caasp_etcd_member'] = True
    except Exception, e:
        log.error(
            'caasp_etcd_member: could not get caasp_etcd_member grain: {}'.format(e))

    return grains


if __name__ == '__main__':
    print _get_etcdctl_peers_urls()
    print _get_local_peer_url()
