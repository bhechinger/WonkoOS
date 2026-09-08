{ pkgs, ... }:

{
  home.packages = with pkgs; [
    kubernetes-helm
    kubectl
    kubeswitch
    krew
    kustomize
    cilium-cli
    chart-testing
    minikube
    kind
    kube-capacity
    argocd
  ];

  programs = {
    k9s.enable = true;
  };
}
