# Домашний медиастек на Proxmox и k3s

Репозиторий описывает домашнюю инфраструктуру для Jellyfin и будущего ARR-стека:

- Terraform создаёт виртуальные машины k3s, NFS-хранилище и LXC с Xray;
- Ansible настраивает NFS, устанавливает k3s и поднимает локальный SOCKS5 gateway;
- Kubernetes запускает Jellyfin, qBittorrent и Prowlarr;
- общие медиаданные хранятся на NFS, а конфигурации приложений — в `local-path` PVC.

## Архитектура


| Узел            | IP              | Назначение                                   |
| --------------- | --------------- | -------------------------------------------- |
| `glass`         | `192.168.1.122` | Proxmox VE                                   |
| `k3s-master`    | `192.168.1.200` | Kubernetes control plane                     |
| `k3s-worker-1`  | `192.168.1.201` | Jellyfin, qBittorrent, Prowlarr              |
| `k3s-worker-2`  | `192.168.1.202` | свободный worker для дальнейшего расширения  |
| `media-storage` | `192.168.1.205` | ext4-диск и NFS export `192.168.1.205:/data` |
| `proxy-xray`    | `192.168.1.177` | SOCKS5 gateway через VLESS/XHTTP/Reality     |


Поток медиаданных:

```text
qBittorrent ──► /data/downloads
                       │
                 Sonarr/Radarr (позже)
                       │
                       ▼
                /data/media/{tv,movies}
                       │
                       ▼
                    Jellyfin
```

Поток запросов к индексерам:

```text
Prowlarr ──SOCKS5──► 192.168.1.177:1080
                              │
                              ▼
                    VLESS/XHTTP/Reality
                              │
                              ▼
                           Internet
```



## Структура новой схемы

```text
modules/base/
├── lxc/                         # базовый Terraform-модуль LXC
└── vm/                          # базовый Terraform-модуль VM

proxmox/
├── .ssh/                        # локальный SSH-ключ, игнорируется Git
├── terraform/                   # Proxmox VM/LXC
├── ansible/
│   ├── files/
│   │   └── xray-config.json.vault  # зашифрованный конфиг, игнорируется Git
│   ├── group_vars/
│   ├── inventory.ini
│   └── playbooks/
│       ├── media_storage_playbook.yaml
│       ├── k3s_playbook.yaml
│       └── proxy_xray_playbook.yaml
└── k3s/
    ├── jellyfin/
    ├── qbittorrent/
    └── prowlarr/
```



## Что понадобится заранее

Утилиты:

- Terraform;
- Ansible;
- `kubectl`;
- SSH-клиент;

На Proxmox должны быть заранее загружены:

- Ubuntu LXC template, указанный в `var.template`;
- Ubuntu cloud image, указанный в `var.vm_cloud_image`;
- HAOS image



## Секреты и локальные файлы

Следующие файлы не должны попадать в Git и уже покрыты `.gitignore`.

### SSH-ключ

Ключ используется Terraform для cloud-init и Ansible для подключения:

```bash
mkdir -p proxmox/.ssh
ssh-keygen -t ed25519 -f proxmox/.ssh/id_proxmox
```



### Terraform variables

Создать `proxmox/terraform/terraform.tfvars`:

```hcl
proxmox_password = "PROXMOX_ROOT_PASSWORD"

# Необязательно, т.к. некоторые штуки, которые мы тут делаем могут выполняться только с паролем рута, таков проксмокс
proxmox_token = ""

vm_cloud_image = "local:import/ubuntu-26.04-server-cloudimg-amd64.img.qcow2"
haos_image      = "haos_ova-15.2.qcow2"
```

При необходимости там же переопределяются:

```hcl
proxmox_endpoint = "https://192.168.1.122:8006"
node_name        = "glass"
gateway          = "192.168.1.1"
template         = "local:vztmpl/ubuntu-26.04-standard_26.04-1_amd64.tar.zst"
```



### Xray Vault

Файл `proxmox/ansible/files/xray-config.json.vault` содержит:

- адрес VLESS-сервера;
- UUID;
- Reality `pbk`, `sid`, `spx` и SNI;
- пароль локального SOCKS5.

Он игнорируется правилом `*vault`, поэтому после клонирования его надо создать заново:

```bash
cd proxmox/ansible
mkdir -p files
ansible-vault create files/xray-config.json.vault
```

Внутри Vault должен находиться JSON формата Xray `v26.7.28`:

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
            "pass": "SOCKS_PASSWORD"
          }
        ],
        "udp": false
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"],
        "routeOnly": true
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

### Kubeconfig

Kubeconfig содержит клиентские ключи администратора кластера. Хранить его следует вне репозитория или в игнорируемом файле с правами `0600`, он генерится при настройке кластера

## Порядок развёртывания



### 1. Проверить Terraform-код

```bash
terraform -chdir=proxmox/terraform init
terraform -chdir=proxmox/terraform fmt -check
terraform -chdir=proxmox/terraform validate
terraform -chdir=proxmox/terraform plan
```

Важно: Terraform root module пока также содержит Home Assistant и legacy LXC `jellyfin`/`prowlarr`. Перед `apply` обязательно прочитать план и убедиться, что он не уничтожает и не пересоздаёт существующие ресурсы. Legacy-ресурсы не являются частью описанного здесь k3s-медиастека.

После проверки сохранить план:

```bash
terraform -chdir=proxmox/terraform plan -out=tfplan
terraform -chdir=proxmox/terraform apply tfplan
```

Новая схема ожидает создание:

- `k3s-master`, `k3s-worker-1`, `k3s-worker-2`;
- `media-storage` с дополнительным диском;
- `proxy-xray` LXC.



### 2. Один раз подготовить медиадиск

Terraform создаёт пустой дополнительный диск, но намеренно не форматирует его. Подключиться к `media-storage` и сначала определить устройство:

```bash
ssh -i proxmox/.ssh/id_proxmox ubuntu@192.168.1.205
lsblk -f
```

Затем создать ext4 только на точно проверенном пустом дополнительном диске.

> `mkfs.ext4` уничтожает существующие данные. Нельзя копировать команду с именем устройства вслепую: сначала надо сверить размер, тип и отсутствие нужных разделов через `lsblk -f`.

После форматирования получить UUID:

```bash
sudo blkid
```

Записать UUID в:

```text
proxmox/ansible/group_vars/media_storage.yaml
```

```yaml
media_filesystem_uuid: "ACTUAL_EXT4_UUID"
```



### 3. Подготовить Ansible

```bash
cd proxmox/ansible
ansible-galaxy collection install -r requirements.yaml
```

Проверить доступность узлов:

```bash
ansible k3s_cluster -m ping
ansible media_storage -m ping
ansible proxy_xray -m ping
```



### 4. Настроить NFS

```bash
ansible-playbook playbooks/media_storage_playbook.yaml
```

Проверить:

```bash
ansible media_storage -b -m command -a "findmnt /data"
ansible media_storage -b -m command -a "exportfs -v"
```

Экспорт должен быть доступен как:

```text
192.168.1.205:/data
```



### 5. Установить k3s

```bash
ansible-playbook playbooks/k3s_playbook.yaml
```

Playbook устанавливает `nfs-common` на все ноды, поднимает server и подключает worker-ноды с использованием автоматически полученного k3s token.

Проверить кластер на master:

```bash
ansible k3s_server -b -m command -a "k3s kubectl get nodes -o wide"
```



### 6. Получить kubeconfig

На рабочем компьютере:

```bash
mkdir -p ~/.kube
ssh -i proxmox/.ssh/id_proxmox ubuntu@192.168.1.200 \
  "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/k3s-home.yaml
chmod 600 ~/.kube/k3s-home.yaml
```

Заменить API endpoint внутри kubeconfig:

```bash
KUBECONFIG=~/.kube/k3s-home.yaml \
  kubectl config set-cluster default --server=https://192.168.1.200:6443
```

Проверить:

```bash
KUBECONFIG=~/.kube/k3s-home.yaml kubectl get nodes
```

Для текущего shell можно выполнить:

```bash
export KUBECONFIG=~/.kube/k3s-home.yaml
```



### 7. Настроить Xray gateway

```bash
cd proxmox/ansible
ansible-playbook playbooks/proxy_xray_playbook.yaml --ask-vault-pass
```

Playbook скачивает зафиксированный официальный release Xray, проверяет SHA-256, устанавливает systemd unit и расшифровывает Vault только на целевом LXC.

Проверить:

```bash
ansible proxy_xray -b -m command -a "/usr/local/bin/xray version"
ansible proxy_xray -b -m command -a "systemctl is-active xray"
ansible proxy_xray -b -m command -a "ss -lntp"
```

Проверить внешний маршрут:

```bash
read -s XRAY_PROXY_PASSWORD
echo
curl \
  --fail \
  --show-error \
  --socks5-hostname 192.168.1.177:1080 \
  --proxy-user "media-stack:${XRAY_PROXY_PASSWORD}" \
  https://api.ipify.org
echo
unset XRAY_PROXY_PASSWORD
```

IP через proxy должен отличаться от прямого `curl https://api.ipify.org`.

### 8. Развернуть NFS PV и Jellyfin

```bash
kubectl apply -f proxmox/k3s/jellyfin/namespace.yaml
kubectl apply -f proxmox/k3s/jellyfin/media-pv.yaml
kubectl apply -f proxmox/k3s/jellyfin/media-pvc.yaml
kubectl apply -f proxmox/k3s/jellyfin/pvc.yaml
kubectl apply -f proxmox/k3s/jellyfin/deployment.yaml
kubectl apply -f proxmox/k3s/jellyfin/service.yaml
```

Проверить:

```bash
kubectl get pv
kubectl get pvc -n jellyfin
kubectl get pods,services -n jellyfin -o wide
kubectl exec -n jellyfin deployment/jellyfin -- ls -la /data
```



### 9. Развернуть qBittorrent

```bash
kubectl apply -f proxmox/k3s/qbittorrent/
kubectl get pods,services -n jellyfin -l app=qbittorrent -o wide
kubectl logs -n jellyfin deployment/qbittorrent
```

NodePort Web UI:

```bash
kubectl get service qbittorrent -n jellyfin
```

В Web UI настроить:

```text
Default Save Path:          /data/downloads
Incomplete Torrents Path:  /data/downloads/incomplete
category movies:           /data/downloads/movies
category tv:               /data/downloads/tv
```

Временный пароль первого входа выводится в логах контейнера. После входа его надо заменить.

### 10. Развернуть Prowlarr

```bash
kubectl apply -f proxmox/k3s/prowlarr/
kubectl get pods,services -n jellyfin -l app=prowlarr -o wide
kubectl logs -n jellyfin deployment/prowlarr
```

В Prowlarr включить аутентификацию Web UI, затем добавить Indexer Proxy:

```text
Type:      SOCKS5
Host:      192.168.1.177
Port:      1080
Username:  media-stack
Password:  значение из Xray Vault
Tag:       xray
```

Индексерам, которые должны использовать VLESS, назначить тег `xray`.

## Проверка итогового состояния

```bash
kubectl get nodes -o wide
kubectl get pv
kubectl get pvc -n jellyfin
kubectl get deployments,pods,services -n jellyfin -o wide
```

Ожидается:

- все k3s-ноды имеют статус `Ready`;
- `media-nfs` и все PVC имеют статус `Bound`;
- Jellyfin, qBittorrent и Prowlarr имеют `1/1 Ready`;
- внутри Jellyfin и qBittorrent виден общий `/data`;
- Prowlarr успешно тестирует SOCKS5 и индексер с тегом `xray`.



## Где хранятся данные


| Данные                | Хранилище                                         |
| --------------------- | ------------------------------------------------- |
| медиатека и загрузки  | NFS `192.168.1.205:/data`                         |
| Jellyfin `/config`    | `local-path`, `k3s-worker-1`                      |
| qBittorrent `/config` | `local-path`, `k3s-worker-1`                      |
| Prowlarr `/config`    | `local-path`, `k3s-worker-1`                      |
| Xray config           | `/usr/local/etc/xray/config.json` на `proxy-xray` |


Конфигурационные PVC привязаны к `k3s-worker-1` и не являются высокодоступными. До добавления распределённого storage для них нужны регулярные резервные копии.

## Что не коммитить

Перед коммитом проверить:

```bash
git status --short
git diff --check
```

В Git не должны попадать:

- `terraform.tfvars`;
- `*.tfstate`;
- приватные SSH-ключи;
- kubeconfig;
- расшифрованный Xray JSON;
- Vault password;
- API keys и пароли приложений/индексеров.

