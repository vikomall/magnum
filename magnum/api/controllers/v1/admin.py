#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

import pecan
from pecan import rest
from wsme import types as wtypes

from magnum.api import expose
from magnum.common import policy
from magnum import objects


class ClusterStats(wtypes.Base):
    clusters = int
    nodes = int

    def __init__(self, clusters=0, nodes=0):
        self.clusters = clusters
        self.nodes = nodes


class ClusterStatsController(rest.RestController):
    """REST controller for stats."""

    def __init__(self, **kwargs):
        super(ClusterStatsController, self).__init__()

    @expose.expose(ClusterStats, int)
    def get_one(self, project_id):
        """Retrieve magnum cluster and node counts.

        """
        context = pecan.request.context
        policy.enforce(context, 'admin:stats', action='admin:stats')

        ret = objects.Cluster.get_stats(pecan.request.context, project_id)
        return ClusterStats(ret[0], ret[1])

    @expose.expose(ClusterStats)
    def get_all(self):
        """Retrieve magnum cluster and node counts.

        """
        context = pecan.request.context
        policy.enforce(context, 'admin:stats', action='admin:stats')

        ret = objects.Cluster.get_stats(pecan.request.context)
        return ClusterStats(ret[0], ret[1])


class AdminController(rest.RestController):
    """REST controller for Admin actions."""

    def __init__(self, **kwargs):
        super(AdminController, self).__init__()

    stats = ClusterStatsController()
