Install ArgoCD:
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
cli:
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64


kubectl get pods -n argocd
NAME                                                READY   STATUS    RESTARTS       AGE
argocd-application-controller-0                     1/1     Running   1 (175m ago)   20h
argocd-applicationset-controller-5b5ccc9759-wkrrz   1/1     Running   1 (175m ago)   20h
argocd-dex-server-5c979b7d88-dslvz                  1/1     Running   1 (175m ago)   20h
argocd-notifications-controller-6f9d5586b-hcfgm     1/1     Running   1 (175m ago)   20h
argocd-redis-5bfb6dfc9f-f5bx6                       1/1     Running   1 (175m ago)   20h
argocd-repo-server-6d4dbbf4b4-n7wxb                 0/1     Unknown   0              20h
argocd-server-c9cdf8dc-8p6dn                        1/1     Running   1 (175m ago)   20h


kubectl port-forward svc/argocd-server -n argocd 8080:443

# print initial admin password
➤ kubectl get secret argocd-initial-admin-secret -n argocd \
        -o jsonpath="{.data.password}" | base64 -d && echo
**********

# insecure because port-forward uses a k8s-generated cert
argocd login localhost:8080 \
  --username admin \
  --password "$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)" \
  --insecure

<!-- .
➤ argocd login localhost:8080 --insecure
Username: admin
Password: *********
'admin:login' logged in successfully
Context 'localhost:8080' updated
.
 -->







argocd repo add https://github.com/neaj-morshad-101/devops-lab
<!-- argocd repo add https://github.com/neaj-morshad-101/devops-lab --insecure-ignore-host-key -->

devops-lab/
  └── postgres/gitops/
       ├── sr.yaml



<!-- argocd app create kubedb \
  --repo https://github.com/neaj-morshad-101/devops-lab \
  --path postgres/gitops \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --sync-policy automated -->


argocd app create kubedb \
  --repo https://github.com/neaj-morshad-101/devops-lab \
  --path ci-cd/gitops \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --sync-policy automated

argocd app list
argocd app get kubedb
argocd app get mongodb-app
kubectl get pods

argocd app sync kubedb
argocd app set kubedb --sync-policy automated


argocd app sync kubedb --prune --retry
--prune → delete resources that exist in the cluster but were removed from Git.
--retry → retry failed resources immediately.