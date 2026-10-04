#!/usr/bin/perl

use strict;
use warnings;
use lib 't/lib';

use Test::Deep;
use Test::Exception;
use Test::More;
use Test::NoWarnings;

use GLPI::Test::Inventory;
use GLPI::Agent::Task::Inventory::Generic::Storages::SmartHealth;

my %health_tests = (
    'nvme-vmware' => {
        SMART_HEALTH            => 100,
        SMART_HEALTH_SOURCE     => 'NVMe Percentage Used',
        SMART_STATUS            => 'PASSED',
        SMART_TYPE              => 'SSD',
        SMART_POWER_ON_HOURS    => 60,
        SMART_TEMPERATURE       => 30,
        SMART_WRITTEN           => 2,
        SMART_CRITICAL_WARNING  => 0,
        SMART_MEDIA_ERRORS      => 0,
    },
    'nvme-worn' => {
        SMART_HEALTH            => 0,
        SMART_HEALTH_SOURCE     => 'NVMe Percentage Used',
        SMART_STATUS            => 'FAILED',
        SMART_TYPE              => 'SSD',
        SMART_POWER_ON_HOURS    => 30000,
        SMART_TEMPERATURE       => 45,
        SMART_WRITTEN           => 153600000,
        SMART_CRITICAL_WARNING  => 4,
        SMART_MEDIA_ERRORS      => 3,
    },
    'ata-samsung-ssd' => {
        SMART_HEALTH                => 93,
        SMART_HEALTH_SOURCE         => 'Device Statistics (Percentage Used)',
        SMART_STATUS                => 'PASSED',
        SMART_TYPE                  => 'SSD',
        SMART_POWER_ON_HOURS        => 8760,
        SMART_TEMPERATURE           => 33,
        SMART_WRITTEN               => 20000000,
        SMART_REALLOCATED_SECTORS   => 0,
    },
    'ata-intel-ssd' => {
        SMART_HEALTH                => 8,
        SMART_HEALTH_SOURCE         => 'Attribute 233 Media_Wearout_Indicator',
        SMART_STATUS                => 'PASSED',
        SMART_TYPE                  => 'SSD',
        SMART_POWER_ON_HOURS        => 31000,
        SMART_TEMPERATURE           => 36,
        SMART_REALLOCATED_SECTORS   => 0,
    },
    'ata-crucial-ssd' => {
        SMART_HEALTH                => 25,
        SMART_HEALTH_SOURCE         => 'Attribute 202 Percent_Lifetime_Remain',
        SMART_STATUS                => 'PASSED',
        SMART_TYPE                  => 'SSD',
        SMART_POWER_ON_HOURS        => 15000,
        SMART_REALLOCATED_SECTORS   => 0,
        SMART_PENDING_SECTORS       => 0,
        SMART_UNCORRECTABLE_SECTORS => 0,
    },
    'ata-hdd-pending' => {
        SMART_STATUS                => 'PASSED',
        SMART_TYPE                  => 'HDD',
        SMART_POWER_ON_HOURS        => 35000,
        SMART_TEMPERATURE           => 41,
        SMART_REALLOCATED_SECTORS   => 16,
        SMART_PENDING_SECTORS       => 8,
        SMART_UNCORRECTABLE_SECTORS => 0,
    },
    'ata-ssd-failing' => {
        SMART_HEALTH                => 60,
        SMART_HEALTH_SOURCE         => 'Attribute 231 SSD_Life_Left',
        SMART_STATUS                => 'FAILED',
        SMART_TYPE                  => 'SSD',
        SMART_POWER_ON_HOURS        => 22000,
        SMART_REALLOCATED_SECTORS   => 2000,
        SMART_FAILING_ATTRIBUTES    => '5 Reallocated_Sector_Ct',
    },
    'ata-ssd-nocounter' => {
        SMART_STATUS                => 'PASSED',
        SMART_TYPE                  => 'SSD',
        SMART_POWER_ON_HOURS        => 1200,
    },
    'scsi-ssd' => {
        SMART_HEALTH            => 88,
        SMART_HEALTH_SOURCE     => 'SCSI Percentage Used',
        SMART_STATUS            => 'PASSED',
        SMART_TYPE              => 'SSD',
        SMART_POWER_ON_HOURS    => 20000,
        SMART_TEMPERATURE       => 30,
    },
    'open-failed' => undef,
);

my %scan_tests = (
    'scan-windows'  => [
        { name => '/dev/sda', info_name => '/dev/sda', type => 'nvme', protocol => 'NVMe' },
    ],
    'scan-linux'    => [
        { name => '/dev/sda', info_name => '/dev/sda [SAT]', type => 'sat', protocol => 'ATA' },
        { name => '/dev/nvme0', info_name => '/dev/nvme0', type => 'nvme', protocol => 'NVMe' },
        { name => '/dev/bus/0', info_name => '/dev/bus/0 [megaraid_disk_00] [SAT]', type => 'sat+megaraid,0', protocol => 'ATA' },
    ],
);

my @windows_storages = (
    { NAME => 'PhysicalDisk0', SERIAL => 'VMware', MODEL => 'VMware Virtual NVMe Disk' },
    { NAME => 'PhysicalDisk1', SERIAL => 'S6PWNX0R123456A', MODEL => 'Samsung SSD 870 EVO 500GB' },
    { NAME => 'PhysicalDisk2', SERIAL => 'VMware', MODEL => 'VMware Virtual SATA Hard Drive' },
    { NAME => '\\\\.\\PHYSICALDRIVE3', SERIAL => 'WD-WCC4N1234567', MODEL => 'WDC WD10EZEX-08WN4A0' },
    { NAME => 'NECVMWar VMware SATA CD01', TYPE => 'DVD-ROM' },
);

my @linux_storages = (
    { NAME => 'sda', SERIALNUMBER => 'OTHERSERIAL' },
    { NAME => 'nvme0n1', SERIALNUMBER => 'S4EWNX0R654321B' },
);

my @match_tests = (
    # [ test name, os, storages, device, serial, expected storage index ]
    [ 'windows: unique serial first word', 'MSWin32', \@windows_storages, '/dev/sdb', 'S6PWNX0R123456A', 1 ],
    [ 'windows: ambiguous serial uses disk number', 'MSWin32', \@windows_storages, '/dev/sdc', 'VMware NVME_0002', 2 ],
    [ 'windows: Win32_DiskDrive name', 'MSWin32', \@windows_storages, '/dev/sdd', undef, 3 ],
    [ 'windows: no match', 'MSWin32', \@windows_storages, '/dev/sdf', 'UNKNOWN0001', undef ],
    [ 'windows: csmi device without serial', 'MSWin32', \@windows_storages, '/dev/csmi0,1', undef, undef ],
    [ 'linux: nvme controller to namespace', 'linux', \@linux_storages, '/dev/nvme0', undef, 1 ],
    [ 'linux: serial match', 'linux', \@linux_storages, '/dev/nvme0', 'S4EWNX0R654321B', 1 ],
    [ 'linux: name match', 'linux', \@linux_storages, '/dev/sda', 'S3Z9NB0K000000X', 0 ],
);

plan tests =>
    (2 * scalar keys %health_tests) +
    (scalar keys %scan_tests)       +
    (scalar @match_tests)           +
    6;

# Only existing modules can be listed as dependencies, or the inventory is aborted
ok(
    GLPI::Agent::Task::Inventory::Generic::Storages::SmartHealth::_moduleExists('GLPI::Agent::Task::Inventory::Win32::Storages'),
    "existing module found"
);
ok(
    !GLPI::Agent::Task::Inventory::Generic::Storages::SmartHealth::_moduleExists('GLPI::Agent::Task::Inventory::Not::Existing'),
    "missing module not found"
);
is(
    scalar(@{$GLPI::Agent::Task::Inventory::Generic::Storages::SmartHealth::runAfterIfEnabled}),
    18,
    "all storage modules found as dependencies"
);

my $inventory = GLPI::Test::Inventory->new();

foreach my $test (sort keys %health_tests) {
    my $file = "resources/generic/smartctl/$test.json";
    my $data = GLPI::Agent::Task::Inventory::Generic::Storages::SmartHealth::_getSmartData(file => $file);
    my $health = GLPI::Agent::Task::Inventory::Generic::Storages::SmartHealth::_getHealth($data);
    cmp_deeply($health, $health_tests{$test}, "$test: parsing");
    SKIP: {
        skip ('no need to test if not defined', 1) unless defined($health);
        lives_ok {
            $inventory->addEntry(section => 'STORAGES', entry => { NAME => $test, %{$health} });
        } "$test: registering";
    }
}

foreach my $test (sort keys %scan_tests) {
    my @devices = GLPI::Agent::Task::Inventory::Generic::Storages::SmartHealth::_getDevices(
        file => "resources/generic/smartctl/$test.json"
    );
    cmp_deeply(\@devices, $scan_tests{$test}, "$test: devices");
}

foreach my $test (@match_tests) {
    my ($name, $os, $storages, $device, $serial, $expected) = @{$test};
    my $storage = GLPI::Agent::Task::Inventory::Generic::Storages::SmartHealth::_findStorage(
        storages => $storages,
        device   => $device,
        serial   => $serial,
        osname   => $os,
    );
    is($storage, defined($expected) ? $storages->[$expected] : undef, $name);
}

# A storage can only receive SMART data once
my %done;
my @storages = ( { NAME => 'sda', SERIALNUMBER => 'SERIAL1234' } );
my $first = GLPI::Agent::Task::Inventory::Generic::Storages::SmartHealth::_findStorage(
    storages => \@storages, device => '/dev/sda', serial => 'SERIAL1234', done => \%done, osname => 'linux',
);
my $second = GLPI::Agent::Task::Inventory::Generic::Storages::SmartHealth::_findStorage(
    storages => \@storages, device => '/dev/sda', serial => 'SERIAL1234', done => \%done, osname => 'linux',
);
ok(defined($first) && !defined($second), "storage matched only once");

# SMART fields are kept by inventory
my $storages = $inventory->getSection('STORAGES');
my ($samsung) = grep { $_->{NAME} eq 'ata-samsung-ssd' } @{$storages};
is($samsung->{SMART_HEALTH}, 93, "SMART_HEALTH kept in STORAGES section");
