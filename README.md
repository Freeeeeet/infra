# Домашний медиастек на Proxmox и k3s

Репозиторий описывает домашнюю инфраструктуру для Jellyfin и ARR-стека:

- Terraform создаёт VM и LXC в Proxmox;
- Ansible настраивает NFS, кластер k3s и Xray gateway;
- Kubernetes запускает Jellyfin, qBittorrent, Prowlarr, FlareSolverr и Sonarr;
- медиатека и загрузки лежат на общем NFS;
- конфигурации приложений лежат в `local-path` PVC на `k3s-worker-1`.

## Текущая архитектура

| Узел | IP | Назначение |
| --- | --- | --- |
| `glass` | `192.168.1.122` | Proxmox VE |
| `k3s-master` | `192.168.1.200` | Kubernetes control plane |
| `k3s-worker-1` | `192.168.1.201` | Jellyfin, qBittorrent, Prowlarr, Sonarr |
| `k3s-worker-2` | `192.168.1.202` | FlareSolverr |
| `media-storage` | `192.168.1.205` | ext4-диск и NFS export `192.168.1.205:/data` |
| `proxy-xray` | `192.168.1.177` | SOCKS5 `:1080` и HTTP proxy `:1081` через VLESS |

Поток медиаданных:

```text
Sonarr -> qBittorrent -> /data/downloads/tv
                              |
                              | hardlink/import
                              v
                       /data/media/tv -> Jellyfin
```

Поток поиска релизов:

```text
Sonarr -> Prowlarr -> SOCKS5 192.168.1.177:1080 -> индексеры
   |
   +-> qBittorrent API -> загрузка
```

Исходящие запросы Sonarr к Skyhook и Jellyfin к провайдерам метаданных идут через HTTP proxy `192.168.1.177:1081`. Локальные адреса Kubernetes и домашней сети исключены через proxy bypass/`NO_PROXY`.

Структура NFS:

```text
/data/
├── downloads/
│   ├── incomplete/
│   ├── movies/
│   └── tv/
└── media/
    ├── movies/
    ├── music/
    └── tv/
```

## Структура репозитория

```text
modules/base/
├── lxc/
└── vm/

proxmox/
├── .ssh/                         # локальный SSH-ключ, игнорируется Git
├── terraform/                    # Proxmox VM/LXC
├── ansible/
│   ├── files/
│   │   └── xray-config-raccoon.json.vault
│   ├── group_vars/
│   ├── inventory.ini
│   └── playbooks/
│       ├── media_storage_playbook.yaml
│       ├── k3s_playbook.yaml
│       └── proxy_xray_playbook.yaml
└── k3s/
    ├── flaresolverr/
    ├── jellyfin/
    ├── prowlarr/
    ├── qbittorrent/
    └── sonarr/
```

## Быстрый старт: подключиться к уже работающему проекту

Этот раздел нужен после нового клонирования репозитория, если инфраструктура уже развёрнута.

### 1. Установить локальные инструменты

Нужны `terraform`, `ansible`, `kubectl`, `ssh` и `git`.

### 2. Восстановить SSH-ключ

Приватный ключ не хранится в Git. Положить существующую пару ключей в:

```text
proxmox/.ssh/id_proxmox
proxmox/.ssh/id_proxmox.pub
```

Права приватного ключа:

```bash
chmod 600 proxmox/.ssh/id_proxmox
```

Новый ключ создавать нельзя, если его публичная часть ещё не добавлена на существующие VM/LXC.

### 3. Получить kubeconfig

```bash
mkdir -p ~/.kube
ssh -i proxmox/.ssh/id_proxmox ubuntu@192.168.1.200 \
  "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/k3s-home.yaml
chmod 600 ~/.kube/k3s-home.yaml

KUBECONFIG=~/.kube/k3s-home.yaml \
  kubectl config set-cluster default --server=https://192.168.1.200:6443
```

Для каждого нового shell:

```bash
export KUBECONFIG=~/.kube/k3s-home.yaml
kubectl config current-context
kubectl get nodes
```

Всегда проверять контекст перед `apply`: обычный `kubectl` может указывать на другой кластер.

### 4. Восстановить секреты только при необходимости управления ими

Для обычной работы с уже запущенными приложениями Kubernetes Secrets повторно создавать не нужно: они уже находятся в кластере. Для повторного запуска Terraform или Ansible понадобятся локальные секреты из раздела [Секреты](#секреты).

Проверка проекта:

```bash
kubectl get deployments,pods,services,pvc -n jellyfin -o wide
kubectl get pv
```

NodePort приложений:

```bash
kubectl get services -n jellyfin
```

## Быстрый старт: развёртывание с нуля

Краткий порядок:

1. Создать SSH-ключ, `terraform.tfvars` и Xray Vault.
2. Выполнить Terraform `plan` и `apply`.
3. Один раз отформатировать дополнительный медиадиск и записать его UUID в Ansible variables.
4. Запустить Ansible для NFS, k3s и Xray.
5. Получить kubeconfig и выбрать домашний контекст.
6. Создать Kubernetes Secrets.
7. Применить Kubernetes-манифесты в указанном порядке.
8. Настроить связи приложений через Web UI.

Подробные команды находятся ниже.

## Секреты

| Секрет | Где нужен | Где хранится |
| --- | --- | --- |
| Приватный SSH-ключ | Terraform/Ansible/получение kubeconfig | `proxmox/.ssh/id_proxmox` |
| Пароль Proxmox | Terraform provider | `proxmox/terraform/terraform.tfvars` |
| VLESS/Reality и proxy password | Xray | `proxmox/ansible/files/xray-config-raccoon.json.vault` |
| URL proxy Jellyfin | Jellyfin | Kubernetes Secret `jellyfin-proxy` |
| Proxy credentials FlareSolverr | FlareSolverr | Kubernetes Secret `flaresolverr-proxy` |
| Пароли и API keys приложений | Web UI интеграции | В конфигурационных PVC приложений |
| Администраторский kubeconfig | `kubectl` | `~/.kube/k3s-home.yaml` |

Секреты и kubeconfig не должны попадать в Git.

### SSH-ключ

При развёртывании с нуля:

```bash
mkdir -p proxmox/.ssh
ssh-keygen -t ed25519 -f proxmox/.ssh/id_proxmox
```

### Terraform variables

Создать `proxmox/terraform/terraform.tfvars`:

```hcl
proxmox_password = "PROXMOX_ROOT_PASSWORD"
proxmox_token    = ""

vm_cloud_image = "local:import/ubuntu-26.04-server-cloudimg-amd64.img.qcow2"
haos_image      = "haos_ova-15.2.qcow2"
```

При необходимости переопределить:

```hcl
proxmox_endpoint = "https://192.168.1.122:8006"
node_name        = "glass"
gateway          = "192.168.1.1"
template         = "local:vztmpl/ubuntu-26.04-standard_26.04-1_amd64.tar.zst"
```

### Xray Vault

Playbook ожидает файл:

```text
proxmox/ansible/files/xray-config-raccoon.json.vault
```

Создать его:

```bash
cd proxmox/ansible
mkdir -p files
ansible-vault create files/xray-config-raccoon.json.vault
```

Vault содержит полный JSON Xray: VLESS/Reality outbound и два аутентифицированных inbound:

```json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "socks-in",
      "listen": "192.168.1.177",
      "port": 1080,
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "users": [
          {
            "user": "media-stack",
            "pass": "PROXY_PASSWORD"
          }
        ],
        "udp": false
      }
    },
    {
      "tag": "http-in",
      "listen": "192.168.1.177",
      "port": 1081,
      "protocol": "http",
      "settings": {
        "accounts": [
          {
            "user": "media-stack",
            "pass": "PROXY_PASSWORD"
          }
        ]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "proxy-out",
      "protocol": "vless",
      "settings": {
        "address": "VLESS_SERVER",
        "port": 443,
        "id": "VLESS_UUID",
        "encryption": "none"
      },
      "streamSettings": {
        "method": "xhttp",
        "security": "reality",
        "xhttpSettings": {
          "path": "/",
          "mode": "packet-up",
          "extra": {
            "xPaddingBytes": "100-1000"
          }
        },
        "realitySettings": {
          "serverName": "dl.google.com",
          "fingerprint": "chrome",
          "password": "REALITY_PBK",
          "shortId": "REALITY_SID",
          "spiderX": "/#EXAMPLE"
        }
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ]
}
```

### Kubernetes Secrets

Сначала выбрать домашний кластер:

```bash
export KUBECONFIG=~/.kube/k3s-home.yaml
kubectl config current-context
```

Текущие манифесты требуют ровно два Kubernetes Secret:

| Deployment | Secret | Обязательные ключи |
| --- | --- | --- |
| `jellyfin` | `jellyfin-proxy` | `url` |
| `flaresolverr` | `flaresolverr-proxy` | `url`, `username`, `password` |

Prowlarr и Sonarr сейчас не используют `secretKeyRef`: их proxy credentials и API keys задаются через Web UI и сохраняются в конфигурационных PVC.

Secret для HTTP proxy Jellyfin:

```bash
read -s XRAY_PROXY_PASSWORD
echo
kubectl create secret generic jellyfin-proxy \
  --namespace jellyfin \
  --from-literal="url=http://media-stack:${XRAY_PROXY_PASSWORD}@192.168.1.177:1081"
unset XRAY_PROXY_PASSWORD
```

Если пароль содержит `@`, `:`, `/`, `#`, `%` или другие специальные URL-символы, его нужно предварительно percent-encode.

Secret для FlareSolverr:

```bash
read -s XRAY_PROXY_PASSWORD
echo
kubectl create secret generic flaresolverr-proxy \
  --namespace jellyfin \
  --from-literal=url=socks5://192.168.1.177:1080 \
  --from-literal=username=media-stack \
  --from-literal=password="$XRAY_PROXY_PASSWORD"
unset XRAY_PROXY_PASSWORD
```

Команды создания Secret выполняются после создания namespace и до соответствующих Deployment. При повторном развёртывании существующий Secret сначала не удалять: использовать `kubectl create ... --dry-run=client -o yaml | kubectl apply -f -` или обновить его осознанно.

Безопасно проверить наличие Secret и имена ключей, не выводя значения:

```bash
kubectl get secrets -n jellyfin -o json | \
  jq '[.items[] | {name: .metadata.name, keys: (.data | keys)}]'
```

## Полное развёртывание

### 1. Подготовить образы Proxmox

На Proxmox заранее должны быть загружены:

- Ubuntu LXC template из `var.template`;
- Ubuntu cloud image из `var.vm_cloud_image`;
- HAOS image из `var.haos_image`.

### 2. Terraform

```bash
terraform -chdir=proxmox/terraform init
terraform -chdir=proxmox/terraform fmt -check
terraform -chdir=proxmox/terraform validate
terraform -chdir=proxmox/terraform plan -out=tfplan
```

Перед `apply` прочитать план и убедиться, что он не уничтожает существующие ресурсы:

```bash
terraform -chdir=proxmox/terraform apply tfplan
```

Terraform создаёт `k3s-master`, два worker, `media-storage`, `proxy-xray` и Home Assistant.

### 3. Один раз подготовить медиадиск

Terraform создаёт пустой дополнительный диск, но намеренно не форматирует его:

```bash
ssh -i proxmox/.ssh/id_proxmox ubuntu@192.168.1.205
lsblk -f
```

`mkfs.ext4` уничтожает данные. Форматировать только точно проверенный пустой дополнительный диск. После форматирования получить UUID:

```bash
sudo blkid
```

Записать UUID в `proxmox/ansible/group_vars/media_storage.yaml`:

```yaml
media_filesystem_uuid: "ACTUAL_EXT4_UUID"
```

### 4. Ansible

```bash
cd proxmox/ansible
ansible-galaxy collection install -r requirements.yaml

ansible k3s_cluster -m ping
ansible media_storage -m ping
ansible proxy_xray -m ping

ansible-playbook playbooks/media_storage_playbook.yaml
ansible-playbook playbooks/k3s_playbook.yaml
ansible-playbook playbooks/proxy_xray_playbook.yaml --ask-vault-pass
```

Проверки:

```bash
ansible media_storage -b -m command -a "findmnt /data"
ansible media_storage -b -m command -a "exportfs -v"
ansible k3s_server -b -m command -a "k3s kubectl get nodes -o wide"
ansible proxy_xray -b -m command -a "systemctl is-active xray"
ansible proxy_xray -b -m command -a "ss -lntp"
```

### 5. Получить kubeconfig

Выполнить команды из раздела [Подключиться к уже работающему проекту](#быстрый-старт-подключиться-к-уже-работающему-проекту), затем:

```bash
export KUBECONFIG=~/.kube/k3s-home.yaml
kubectl get nodes -o wide
```

### 6. Kubernetes

Сначала namespace и общий NFS:

```bash
kubectl apply -f proxmox/k3s/jellyfin/namespace.yaml
kubectl apply -f proxmox/k3s/jellyfin/media-pv.yaml
kubectl apply -f proxmox/k3s/jellyfin/media-pvc.yaml
```

Создать `jellyfin-proxy` и `flaresolverr-proxy` командами из раздела [Kubernetes Secrets](#kubernetes-secrets).

Применить приложения:

```bash
kubectl apply -f proxmox/k3s/jellyfin/pvc.yaml
kubectl apply -f proxmox/k3s/jellyfin/deployment.yaml
kubectl apply -f proxmox/k3s/jellyfin/service.yaml

kubectl apply -f proxmox/k3s/qbittorrent/
kubectl apply -f proxmox/k3s/prowlarr/
kubectl apply -f proxmox/k3s/flaresolverr/
kubectl apply -f proxmox/k3s/sonarr/
```

Проверить:

```bash
kubectl get pv
kubectl get pvc -n jellyfin
kubectl get deployments,pods,services -n jellyfin -o wide
kubectl exec -n jellyfin deployment/sonarr -- ls -la /data
kubectl exec -n jellyfin deployment/jellyfin -- ls -la /data
```

## Настройка приложений

### qBittorrent

Временный пароль первого входа находится в логах:

```bash
kubectl logs -n jellyfin deployment/qbittorrent
kubectl get service qbittorrent -n jellyfin
```

В Web UI настроить:

```text
Default Save Path:         /data/downloads
Incomplete Torrents Path: /data/downloads/incomplete
category movies:          /data/downloads/movies
category tv:              /data/downloads/tv
```

После первого входа сменить пароль.

### Prowlarr и FlareSolverr

В Prowlarr включить аутентификацию Web UI и добавить Indexer Proxy:

```text
Type:      SOCKS5
Host:      192.168.1.177
Port:      1080
Username:  media-stack
Password:  пароль из Xray Vault
Tag:       xray
```

Индексерам, которым нужен proxy, назначить тег `xray`.

Для защищённого Cloudflare индексера добавить FlareSolverr в Prowlarr:

```text
Host: http://flaresolverr:8191
Tag:  тег соответствующего индексера
```

### Sonarr

Включить Web UI authentication. Root Folder:

```text
/data/media/tv
```

Download Client qBittorrent:

```text
Host:     qbittorrent
Port:     8080
Category: tv
```

Remote Path Mapping не нужен: Sonarr и qBittorrent видят общий том как `/data`.

В `Settings -> Media Management -> Show Advanced` включить `Use Hardlinks instead of Copy`.

Встроенный proxy Sonarr:

```text
Type:                         HTTP
Host:                         192.168.1.177
Port:                         1081
Username:                     media-stack
Password:                     пароль из Xray Vault
Bypass Proxy for Local Addresses: Yes
```

Добавить Sonarr в `Prowlarr -> Settings -> Apps`:

```text
Sync Level:      Full Sync
Prowlarr Server: http://prowlarr:9696
Sonarr Server:   http://sonarr:8989
API Key:         Sonarr -> Settings -> General
```

Prowlarr синхронизирует индексеры в Sonarr. qBittorrent всё равно настраивается непосредственно в Sonarr, потому что Prowlarr ищет релизы, а qBittorrent скачивает их.

### Jellyfin

Создать библиотеку сериалов:

```text
Content type: Shows
Folder:       /data/media/tv
```

Deployment получает `HTTP_PROXY` и `HTTPS_PROXY` из Secret `jellyfin-proxy`. Проверка доступа к TMDB:

```bash
kubectl exec -n jellyfin deployment/jellyfin -- \
  sh -c 'curl -sS -o /dev/null -w "HTTP=%{http_code} total=%{time_total}\n" --max-time 20 https://api.themoviedb.org'
```

Ответ `401`, `403` или `404` означает, что соединение установлено. `000`, timeout или `407` требуют проверки сети/Secret.

## Проверка итогового состояния

```bash
export KUBECONFIG=~/.kube/k3s-home.yaml
kubectl get nodes -o wide
kubectl get pv
kubectl get pvc -n jellyfin
kubectl get deployments,pods,services -n jellyfin -o wide
```

Ожидается:

- все три k3s-ноды имеют статус `Ready`;
- `media-nfs` и все PVC имеют статус `Bound`;
- Jellyfin, qBittorrent, Prowlarr, FlareSolverr и Sonarr имеют `1/1 Ready`;
- Jellyfin, qBittorrent и Sonarr видят общий `/data`;
- Prowlarr тестирует индексер через Xray;
- Sonarr отправляет загрузки в qBittorrent с категорией `tv`;
- готовые серии появляются в `/data/media/tv` и в Jellyfin.

## Где хранятся данные

| Данные | Хранилище |
| --- | --- |
| Загрузки и медиатека | NFS `192.168.1.205:/data` |
| Jellyfin `/config` | `local-path`, `k3s-worker-1` |
| qBittorrent `/config` | `local-path`, `k3s-worker-1` |
| Prowlarr `/config` | `local-path`, `k3s-worker-1` |
| Sonarr `/config` | `local-path`, `k3s-worker-1` |
| Xray config | `/usr/local/etc/xray/config.json` на `proxy-xray` |

Конфигурационные PVC не являются высокодоступными. Для них нужны регулярные резервные копии.

## Что не коммитить

Перед коммитом:

```bash
git status --short
git diff --check
```

В Git не должны попадать:

- `terraform.tfvars` и другие `*.tfvars`;
- `*.tfstate`;
- приватные SSH-ключи;
- kubeconfig;
- расшифрованный Xray JSON и Vault password;
- YAML-файлы с Kubernetes Secrets;
- API keys, proxy URL с паролем и пароли приложений/индексеров.
