#pulp_resource

[Module description]: #module-description

#### Talbe of Contents

1. [Module description - What is the pulp_resource module, and what does it do?][Module description]


## Module description
This module defines custom types and providers to manage pulp server resources, including repo, user, role, user permission and role permission.

## Set up

**What the pulp_resource module required:**

- puppetlabs/inifile module: A inifile utility class is used. The built-in puppet/util/inifile does not allow customized key value seperator
- working pulp-admin client installation
- ~/.pulp/admin.conf with auth configuration
 
```
[auth]
username: admin
password: admin
```
> **Note**: This module use credentials from admin.conf to login, so a user certificate is generated. It uses the certificate for operations later on.
It checks the certificate expiration date and logins again if necessary.

### Beginning with pulp_resource

Declaring pulp_resource class to include custom types.

```puppet
class {'pulp_resource':
}
```

### Managing pulp resources with custom types

#### Pulp repos####

Listing pulp repos: (other resource types works similarly)
```bash
[root@localhost ~]# puppet resource pulp_repo
pulp_repo { 'test':
  ensure      => 'present',
  description => 'test rpm repo',
  serve_http  => 'false',
  serve_https => 'true',
  type        => 'rpm',
}
pulp_repo { 'test_rpm':
  ensure       => 'present',
  description  => '"test rpm"',
  display_name => '"Test RPM Repo"',
  serve_http   => 'false',
  serve_https  => 'true',
  type         => 'rpm',
}
pulp_repo { 'test_rpm2':
  ensure      => 'present',
  description => '2test rpm repo',
  serve_http  => 'false',
  serve_https => 'true',
  type        => 'rpm',
}
pulp_repo { 'test_rpm_rpm':
  ensure       => 'present',
  description  => 'test rpm',
  display_name => 'Test RPM Repo',
  serve_http   => 'false',
  serve_https  => 'true',
  type         => 'rpm',
}
```

Create a pulp repository:

```puppet
pulp_repo {'test_rpm':
 ensure => 'present',
 description => 'test rpm repository',
 display_name => 'Test RPM Repository',
 feed => 'http://dummy',
 serve_http => 'false',
 serve_https => 'true',
 type => 'rpm',
}
```

Create a pulp user:

>**Note** A password field is required, but it is only effective when the user is created.

```puppet
pulp_user {'test':
 ensure => 'present',
 roles => ['super-user'],
 password => 'test',
}
```

Create a pulp role:

```puppet
pulp_role {'testrole':
  ensure => 'present',
  description => 'test role',
}
```

