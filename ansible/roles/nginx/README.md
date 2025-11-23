# Nginx Role

Manages nginx web server configuration with support for multiple virtual hosts, basic authentication, and secure defaults.

## Purpose

This role configures nginx as a web server for hosting static sites with flexible access control. It handles virtual host configuration, directory permissions, basic HTTP authentication, and provides a secure catch-all default server.

## Requirements

- **Target OS**: Debian/Ubuntu Linux (uses APT)
- **Privileges**: Requires `become: true` (sudo/root access)
- **Network**: HTTP(S) ports must be accessible
- **Python**: Python 3 on target hosts (for htpasswd generation)

## Role Variables

### Default Variables

Defined in `defaults/main.yml`:

```yaml
nginx_sites:
  - server_name: tmp.quietlife.net
    root: /var/www/tmp.quietlife.net
    owner: cwage
    group: cwage
    dir_mode: '0750'
    file_mode: '0640'
  
  - server_name: books.quietlife.net
    root: /var/www/books.quietlife.net
    owner: cwage
    group: cwage
    dir_mode: '0750'
    file_mode: '0640'
    basic_auth:
      realm: "Books"
      users:
        - username: books
          password_hash: "$apr1$FNJE//Et$2SbsI8ws4cPCWQexEzrbb0"
```

### Variable Structure

Each site in `nginx_sites` supports:

```yaml
nginx_sites:
  - server_name: example.com          # Required: hostname for this site
    root: /var/www/example.com        # Required: web root directory
    owner: username                   # Required: directory owner
    group: groupname                  # Required: directory group
    dir_mode: '0750'                  # Required: directory permissions
    file_mode: '0640'                 # Required: file permissions
    basic_auth:                       # Optional: HTTP basic authentication
      realm: "Protected Area"         # Auth realm name
      users:                          # List of users
        - username: user1
          password_hash: "$apr1$..."  # APR1 MD5 hash
```

### Generating Password Hashes

```bash
# Using openssl (available everywhere)
openssl passwd -apr1 'your-password'

# Using htpasswd (if apache2-utils installed)
htpasswd -nbm username password
```

## Dependencies

None. This is a standalone role.

## Example Usage

### Basic Playbook

```yaml
---
- name: Configure nginx web server
  hosts: linode_vps
  become: true
  roles:
    - nginx
```

### Example Inventory Configuration

In `inventories/host_vars/felix.yml`:

```yaml
---
nginx_sites:
  # Public site - no authentication
  - server_name: blog.example.com
    root: /var/www/blog
    owner: deploy
    group: www-data
    dir_mode: '0755'
    file_mode: '0644'

  # Protected site - basic auth
  - server_name: private.example.com
    root: /var/www/private
    owner: deploy
    group: www-data
    dir_mode: '0750'
    file_mode: '0640'
    basic_auth:
      realm: "Private Area"
      users:
        - username: admin
          password_hash: "$apr1$xyz123..."
        - username: guest
          password_hash: "$apr1$abc456..."
```

### Running the Role

```bash
# Via VPS playbook
cd ansible
make felix-check  # Preview changes
make felix        # Apply changes
```

## What This Role Does

### 1. Install Nginx and Dependencies

Installs:
- `nginx` — Web server
- `python3-passlib` — For htpasswd file generation

### 2. Configure www-data User

- Adds `www-data` to groups specified in site configurations
- Allows nginx to read files owned by different users
- Example: If site owned by `cwage:cwage`, adds `www-data` to `cwage` group

### 3. Configure Catch-All Default Server

Creates `/etc/nginx/sites-available/00-default`:
```nginx
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 444;  # Close connection without response
}
```

**Purpose**: Prevents nginx from serving arbitrary sites for unmatched Host headers.

### 4. Create Web Root Directories

For each site:
- Creates directory at `root` path
- Sets ownership to specified `owner:group`
- Sets permissions to `dir_mode`
- Creates parent directories if needed

### 5. Create Placeholder index.html

For each site (if doesn't exist):
```html
<!DOCTYPE html>
<html>
<head>
    <title>example.com</title>
</head>
<body>
</body>
</html>
```

**Note**: Uses `force: false` — won't overwrite existing files.

### 6. Configure Basic Authentication

For sites with `basic_auth` defined:
- Creates `/etc/nginx/htpasswd/<server_name>`
- Formats: `username:password_hash` (one per line)
- Permissions: `0640` (readable by nginx)
- Owner: `root:www-data`

### 7. Configure Virtual Hosts

For each site:
- Renders `vhost.conf.j2` template
- Validates with `nginx -t` before deploying
- Enables site by symlinking to `sites-enabled/`
- Triggers nginx reload on changes

### 8. Ensure Nginx is Running

- Starts nginx if not running
- Enables nginx to start on boot
- Reloads configuration when changed

## Outputs

After running this role:
- Nginx is installed and running
- Virtual hosts are configured and enabled
- Web root directories exist with correct permissions
- Sites with basic_auth are password-protected
- Catch-all default prevents directory listing/errors for unmapped domains

## Templates

### vhost.conf.j2

Template for nginx virtual host configuration. Located in `templates/vhost.conf.j2`:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name {{ item.server_name }};
    
    root {{ item.root }};
    index index.html index.htm;
    
    {% if item.basic_auth is defined %}
    auth_basic "{{ item.basic_auth.realm }}";
    auth_basic_user_file /etc/nginx/htpasswd/{{ item.server_name }};
    {% endif %}
    
    location / {
        try_files $uri $uri/ =404;
    }
}
```

## Assumptions and Limitations

### Assumptions
- Target users/groups exist (create with users role first)
- DNS points to the server (nginx doesn't handle DNS)
- HTTP (port 80) is sufficient (no HTTPS/SSL in this role)
- Static sites only (no PHP, Python, etc.)

### Limitations
- No SSL/TLS support (consider Let's Encrypt integration)
- No reverse proxy configuration
- No custom location blocks
- No rate limiting or advanced security headers
- No log rotation configuration (uses system defaults)

### Security Considerations

**Strengths:**
- ✅ Catch-all default prevents information disclosure
- ✅ Basic auth for protected content
- ✅ Restrictive file permissions
- ✅ www-data only gets access to specified groups

**Weaknesses:**
- ❌ No HTTPS (credentials sent in cleartext with basic auth)
- ❌ No rate limiting (vulnerable to DoS)
- ❌ No security headers (CSP, HSTS, etc.)
- ❌ No fail2ban integration

**Recommendations:**
- Add HTTPS with Let's Encrypt (certbot role)
- Use VPN or IP restrictions for sensitive sites
- Consider fail2ban for brute force protection
- Add security headers for production

## Integration with Other Roles

Typical role order:
1. **Users role**: Create site owners
2. **System role**: Configure hostname
3. **Nginx role**: Configure web server
4. **Application roles**: Deploy content

## Common Issues

**"Permission denied" when accessing sites:**
- Check directory permissions: `ls -la /var/www/`
- Verify www-data is in owner group: `groups www-data`
- Check nginx error log: `/var/log/nginx/error.log`
- SELinux may be blocking: `setenforce 0` (test only)

**"404 Not Found" for existing files:**
- Check file exists: `ls /var/www/site/index.html`
- Verify nginx config: `nginx -t`
- Check file permissions: `namei -l /var/www/site/index.html`
- Look for typos in `server_name` or `root`

**Basic auth not working:**
- Verify htpasswd file exists: `ls /etc/nginx/htpasswd/`
- Check file permissions: `ls -l /etc/nginx/htpasswd/`
- Test auth: `curl -u user:pass http://site.com/`
- Check nginx error log for auth failures

**"nginx: [emerg] bind() to 0.0.0.0:80 failed":**
- Another service is using port 80: `netstat -tlnp | grep :80`
- Apache might be running: `systemctl stop apache2`
- Check for conflicting containers

**Sites not accessible from outside:**
- Check firewall rules: `ufw status`
- Verify nginx is listening: `netstat -tlnp | grep nginx`
- Check DNS resolution: `dig example.com`
- Test from server: `curl -H "Host: example.com" localhost`

## Testing

```bash
# Check nginx config
ansible linode_vps -m shell -a "nginx -t" --become

# Check nginx is running
ansible linode_vps -m shell -a "systemctl status nginx" --become

# List configured sites
ansible linode_vps -m shell -a "ls /etc/nginx/sites-enabled/" --become

# Check htpasswd files
ansible linode_vps -m shell -a "ls -l /etc/nginx/htpasswd/" --become

# Test site from server
ansible linode_vps -m shell -a "curl -I localhost"

# Test basic auth
ansible linode_vps -m shell -a "curl -I -u user:pass http://localhost" -e "Host: books.quietlife.net"
```

## Advanced Configuration

### Multiple Authentication Users

```yaml
nginx_sites:
  - server_name: team.example.com
    root: /var/www/team
    owner: deploy
    group: www-data
    dir_mode: '0750'
    file_mode: '0640'
    basic_auth:
      realm: "Team Area"
      users:
        - username: alice
          password_hash: "$apr1$..."
        - username: bob
          password_hash: "$apr1$..."
        - username: charlie
          password_hash: "$apr1$..."
```

### Public and Private Sites

```yaml
nginx_sites:
  # Public site
  - server_name: www.example.com
    root: /var/www/public
    owner: deploy
    group: www-data
    dir_mode: '0755'
    file_mode: '0644'

  # Admin area
  - server_name: admin.example.com
    root: /var/www/admin
    owner: deploy
    group: www-data
    dir_mode: '0750'
    file_mode: '0640'
    basic_auth:
      realm: "Admin Access"
      users:
        - username: admin
          password_hash: "$apr1$..."
```

## Future Enhancements

- SSL/TLS certificate management (Let's Encrypt)
- Reverse proxy configuration
- Custom location blocks
- Security headers configuration
- Log rotation
- Rate limiting
- Fail2ban integration
- IPv6 support verification

## Related Documentation

- [Getting Started Guide](../../../docs/getting-started.md) — Initial setup
- [Users Role](../users/README.md) — Creating site owners
- [Nginx Documentation](https://nginx.org/en/docs/) — Official nginx docs
- [HTTP Basic Auth](https://developer.mozilla.org/en-US/docs/Web/HTTP/Authentication) — Auth mechanism details
