function New-CIPPRestoreTask {
    [CmdletBinding()]
    param (
        $Task,
        $TenantFilter,
        $backup,
        $overwrite
    )
    $Table = Get-CippTable -tablename 'ScheduledBackup'
    $BackupData = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$backup'"
    $RestoreData = switch ($Task) {
        'users' {
            Write-Host "Restore users for $TenantFilter"
            $currentUsers = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users?$top=999' -tenantid $TenantFilter
            $BackupUsers | ForEach-Object {
                try {
                    if ($overwrite) {
                        $currentUsers | Where-Object { $_.id -eq $_.id } | ForEach-Object {
                            New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/users/$($_.id)" -tenantid $TenantFilter -body $_ -type PATCH
                            Write-LogMessage -message "Restored $($_.userprincipalname) from backup" -Sev 'info'
                            "Restored $($_.userprincipalname) from backup"
                        }
                    } else {
                        if ($currentUsers.id -notin $_.id) {
                            New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/users' -tenantid $TenantFilter -body $_ -type POST
                            Write-LogMessage -message "Restored $($_.userprincipalname) from backup" -Sev 'info'
                            "Restored $($_.userprincipalname) from backup"

                        } else {
                            Write-LogMessage -message "User $($_.userPrincipalName) already exists in tenant $TenantFilter and overwrite is disabled" -Sev 'info'
                            "User $($_.userPrincipalName) already exists in tenant $TenantFilter and overwrite is disabled"
                        }
                    }
                } catch {
                    "Could not restore user $($_.userPrincipalName): $($_.Exception.Message) "
                    Write-LogMessage -user $ExecutingUser -API $APINAME -message "Could not restore user $($_.userPrincipalName): $($_.Exception.Message) " -Sev 'error'
                }
            }
        }
        'groups' {
            Write-Host "Restore groups for $TenantFilter"
            $Groups = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$top=999' -tenantid $TenantFilter
            $BackupGroups | ForEach-Object {
                try {
                    if ($overwrite) {
                        $currentUsers | Where-Object { $_.id -eq $_.id } | ForEach-Object {
                            New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/groups/$($_.id)" -tenantid $TenantFilter -body $_ -type PATCH
                            Write-LogMessage -message "Restored $($_.userprincipalname) from backup" -Sev 'info'
                            "Restored group $($_.displayName) from backup"
                        }
                    } else {
                        if ($currentUsers.id -notin $_.id) {
                            New-GraphPOSTRequest -uri 'https://graph.microsoft.com/groups/' -tenantid $TenantFilter -body $_ -type POST
                            Write-LogMessage -message "Restored $($_.userprincipalname) from backup" -Sev 'info'
                            "Restored group $($_.displayName) from backup"

                        } else {
                            Write-LogMessage -message "group $($_.group) already exists in tenant $TenantFilter and overwrite is disabled" -Sev 'info'
                            "group $($_.displayName) already exists in tenant $TenantFilter and overwrite is disabled"
                        }
                    }
                } catch {
                    "Could not restore user $($_.userPrincipalName): $($_.Exception.Message) "
                    Write-LogMessage -user $ExecutingUser -API $APINAME -message "Could not restore user $($_.userPrincipalName): $($_.Exception.Message) " -Sev 'error'
                }
            }
        }
        'ca' {
            Write-Host "Backup Conditional Access Policies for $TenantFilter"
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/conditionalAccess/policies?$top=999' -tenantid $TenantFilter
        }
        'namedlocations' {
            Write-Host "Backup Named Locations for $TenantFilter"
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/conditionalAccess/namedLocations?$top=999' -tenantid $TenantFilter
        }
        'authstrengths' {
            Write-Host "Backup Authentication Strength Policies for $TenantFilter"
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/conditionalAccess/authenticationStrength/policies' -tenantid $TenantFilter
        }
        'intuneconfig' {
            $GraphURLS = @("https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$select=id,displayName,lastModifiedDateTime,roleScopeTagIds,microsoft.graph.unsupportedDeviceConfiguration/originalEntityTypeName&`$expand=assignments&top=1000"
                'https://graph.microsoft.com/beta/deviceManagement/windowsDriverUpdateProfiles'
                "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations?`$expand=assignments&top=999"
                "https://graph.microsoft.com/beta/deviceAppManagement/mobileAppConfigurations?`$expand=assignments&`$filter=microsoft.graph.androidManagedStoreAppConfiguration/appSupportsOemConfig%20eq%20true"
                'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies'
            )

            $GraphURLS | ForEach-Object {
                $URLName = (($_).split('?') | Select-Object -First 1) -replace 'https://graph.microsoft.com/beta/deviceManagement/', ''
                New-GraphGetRequest -uri "$($_)" -tenantid $TenantFilter
            } | ForEach-Object {
                New-CIPPIntuneTemplate -TenantFilter $TenantFilter -URLName $URLName -ID $_.ID
            }
        }
        'intunecompliance' {
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies?$top=999' -tenantid $TenantFilter | ForEach-Object {
                New-CIPPIntuneTemplate -TenantFilter $TenantFilter -URLName 'deviceCompliancePolicies' -ID $_.ID
            }
        }

        'intuneprotection' {
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceAppManagement/managedAppPolicies?$top=999' -tenantid $TenantFilter | ForEach-Object {
                New-CIPPIntuneTemplate -TenantFilter $TenantFilter -URLName 'managedAppPolicies' -ID $_.ID
            }
        }

        'CippWebhookAlerts' {
            Write-Host "Backup Webhook Alerts for $TenantFilter"
            $WebhookTable = Get-CIPPTable -TableName 'WebhookRules'
            Get-CIPPAzDataTableEntity @WebhookTable | Where-Object { $TenantFilter -in ($_.Tenants | ConvertFrom-Json).fullvalue.defaultDomainName }
        }
        'CippScriptedAlerts' {
            Write-Host "Backup Scripted Alerts for $TenantFilter"
            $ScheduledTasks = Get-CIPPTable -TableName 'ScheduledTasks'
            Get-CIPPAzDataTableEntity @ScheduledTasks | Where-Object { $_.hidden -eq $true -and $_.command -like 'Get-CippAlert*' -and $TenantFilter -in $_.Tenant }
        }
        'CippStandards' {
            Write-Host "Backup Standards for $TenantFilter"
            $Table = Get-CippTable -tablename 'standards'
            $Filter = "PartitionKey eq 'standards' and RowKey eq '$($TenantFilter)'"
            (Get-CIPPAzDataTableEntity @Table -Filter $Filter)
        }

    }
    return $RestoreData
}
