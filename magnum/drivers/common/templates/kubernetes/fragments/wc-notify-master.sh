#!/bin/sh

. /etc/sysconfig/heat-params

WC_NOTIFY_BIN=/usr/local/bin/wc-notify
WC_NOTIFY_SERVICE=/etc/systemd/system/wc-notify.service

cat > /tmp/fluentd-daemonset.yaml << EOF
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: fluentd-elasticsearch
  namespace: kube-system
  labels:
    k8s-app: fluentd-logging
spec:
  template:
    metadata:
      labels:
        app: fluentd
    spec:
      containers:
      - name: fluentd-elasticsearch
        image: gcr.io/google_containers/fluentd-elasticsearch:1.20
        resources:
          limits:
            memory: 200Mi
          requests:
            cpu: 100m
            memory: 200Mi
        volumeMounts:
        - name: varlog
          mountPath: /var/log
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
EOF

cat > /tmp/es-pod-service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch-logging
  namespace: kube-system
  labels:
    k8s-app: elasticsearch-logging
    kubernetes.io/cluster-service: "true"
    kubernetes.io/name: "Elasticsearch"
spec:
  ports:
  - port: 9200
    protocol: TCP
    targetPort: db
  selector:
    k8s-app: elasticsearch-logging

---

apiVersion: v1
kind: ReplicationController
metadata:
  name: elasticsearch-logging-v1
  namespace: kube-system
  labels:
    k8s-app: elasticsearch-logging
    version: v1
    kubernetes.io/cluster-service: "true"
spec:
  replicas: 2
  selector:
    k8s-app: elasticsearch-logging
    version: v1
  template:
    metadata:
      labels:
        k8s-app: elasticsearch-logging
        version: v1
        kubernetes.io/cluster-service: "true"
    spec:
      containers:
      - image: gcr.io/google_containers/elasticsearch:v2.4.1
        name: elasticsearch-logging
        resources:
          # need more cpu upon initialization, therefore burstable class
          limits:
            cpu: 1000m
          requests:
            cpu: 100m
        ports:
        - containerPort: 9200
          name: db
          protocol: TCP
        - containerPort: 9300
          name: transport
          protocol: TCP
        volumeMounts:
        - name: es-persistent-storage
          mountPath: /data
      volumes:
      - name: es-persistent-storage
        emptyDir: {}
EOF

cat > /tmp/kibana-pod-service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: kibana-logging
  namespace: kube-system
  labels:
    k8s-app: kibana-logging
    kubernetes.io/cluster-service: "true"
    kubernetes.io/name: "Kibana"
spec:
  ports:
  - port: 5601
    protocol: TCP
    targetPort: ui
  selector:
    k8s-app: kibana-logging

---

apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: kibana-logging
  namespace: kube-system
  labels:
    k8s-app: kibana-logging
    kubernetes.io/cluster-service: "true"
spec:
  replicas: 1
  selector:
    matchLabels:
      k8s-app: kibana-logging
  template:
    metadata:
      labels:
        k8s-app: kibana-logging
    spec:
      containers:
      - name: kibana-logging
        image: gcr.io/google_containers/kibana:v4.6.1
        resources:
          # keep request = limit to keep this container in guaranteed class
          limits:
            cpu: 100m
          requests:
            cpu: 100m
        env:
          - name: "ELASTICSEARCH_URL"
            value: "http://elasticsearch-logging:9200"
          - name: "KIBANA_BASE_URL"
            value: "/api/v1/proxy/namespaces/kube-system/services/kibana-logging"
        ports:
        - containerPort: 5601
          name: ui
          protocol: TCP
EOF

cat > $WC_NOTIFY_BIN <<EOF
#!/bin/bash -v
until curl -sf "http://127.0.0.1:8080/healthz"; do
    echo "Waiting for Kubernetes API..."
    sleep 5
done
kubectl create -f /tmp/fluentd-daemonset.yaml
kubectl create -f /tmp/es-pod-service.yaml
kubectl create -f /tmp/kibana-pod-service.yaml
$WAIT_CURL --data-binary '{"status": "SUCCESS"}'
EOF

cat > $WC_NOTIFY_SERVICE <<EOF
[Unit]
Description=Notify Heat
After=docker.service etcd.service
Requires=docker.service etcd.service
[Service]
Type=oneshot
ExecStart=$WC_NOTIFY_BIN
[Install]
WantedBy=multi-user.target
EOF

chown root:root $WC_NOTIFY_BIN
chmod 0755 $WC_NOTIFY_BIN

chown root:root $WC_NOTIFY_SERVICE
chmod 0644 $WC_NOTIFY_SERVICE

systemctl enable wc-notify
systemctl start --no-block wc-notify