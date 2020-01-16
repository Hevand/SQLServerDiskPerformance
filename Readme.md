# Performance optimization of SQL Server VMs
## Introduction to performance optimization
Performance is at the foundation of every successful application. When moving to the cloud, differences in underlying infrastructure characteristics may surface performance issues that were not visible / as prominent on premises. 

Your strategy to address these issues depends on the current involvement of the development team:

### Scenario 1: Development team is available 
When there is a standing team that is responsible for developing or running any application, organizations will spend substantial time and effort in identifying and addressing any performance bottleneck with an (substantial) impact on end-user experience or scalability. 

For example, teams may look at the following:
- Code paths that can be optimized for performance 
- Application architecture, introducing event-based concepts / asynchronous processing
- Reducing data volumes, by being more selective in their queries / operations or by compressing data as it is being transferred over the wire 
- Bringing data and compute closer together. 
- Evaluate sequential cross-process calls (e.g. API, database, cache) and consider combining them, to reduce network latency and avoid processes that are 'busy waiting'
- Infrastructure optimizations, balancing costs and performance. E.g. adding CPU or memory.

### Scenario 2: Development team is unavailable
In the real world, not every application an organization hosts will have a development team with the capacity to investigate and address all of the above. This holds for legacy applications and commercial products. Even if the application can be changed, it might not be possible or desirable to roll out these changes to all production environment. 

In this situation, it will be the responsibility of the operations team to identify infrastructure limitations and optimize their environment for that. 

## SQL Server Performance Considerations
A relational database like SQL Server is a key component of many applications and a natural focus point when it comes to evaluating application performance. 

On Azure, there are essentially 3 different ways of running SQL Server: 
- SQL Server installed on a Windows VM (IaaS)
- SQL Database (PaaS) on the Standard / General Purpose tier
- SQL Database (PaaS) on the Premium / Business Critical tier

On the IaaS services, Microsoft offers guidance on the configuration: (https://docs.microsoft.com/en-us/azure/virtual-machines/windows/sql/virtual-machines-windows-sql-performance). When you deploy a SQL Server machine from the market place, this guidance is embedded in the default configuration. 

On the PaaS services, Microsoft offers SQL Database on a DTU-based, vCore-based or Managed Instance-based model. Here, Microsoft configures and manages the environment. The system and disk configuration is detailed here: 
- [Standard / General Purpose](https://docs.microsoft.com/en-us/azure/sql-database/sql-database-high-availability#basic-standard-and-general-purpose-service-tier-availability)
![Illustration: Standard / General Purpose](https://docs.microsoft.com/en-us/azure/sql-database/media/sql-database-high-availability/general-purpose-service-tier.png)

- [Premium / Business Critical](https://docs.microsoft.com/en-us/azure/sql-database/sql-database-high-availability#premium-and-business-critical-service-tier-availability)
![Illustration: Premium / Business Critical](https://docs.microsoft.com/en-us/azure/sql-database/media/sql-database-high-availability/business-critical-service-tier.png)

In practice, the performance realized by your SQL environment will be a combination of CPU, Memory and Disk performance. It is crucial to understand each of these factors and their impact on your application. 

For this article, we'll limit our focus on the disk performance. 

As explained [here](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/premium-storage-performance), disk performance is qualified by:
- IOPS
- Throughput
- Latency

Both [Virtual Machines](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/sizes) and [Managed Disks](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/disk-scalability-targets) provide scalability targets and apply throttling on the amount of IOPS and Throughput available. 

> This approach differs from a typical on-premises situation with a [Storage Area Network](https://en.wikipedia.org/wiki/Storage_area_network). On a SAN, a certain maximum number of IOPS / Throughput all connected processes benefit from the maximum IOPS / Throughput that is offered - but also suffer from any 'noisy neighbour' that may exist. This unpredictable Quality of Service is undesirable on a public cloud such as Azure. Instead, Microsoft will actually allocate the capacity that is advertised to your VM / Disk. 

For IOPS and Throughput, the combination of these limits results in the actual IOPS and Throughput available to a SQL Server machine. Actual utilization can be monitored from within the Azure Portal, and you can scale up the VM and available disks (either by scaling or striping) until your application's resource utilization stays under the maximum available capacity. 

### What if IOPS and Throughput are under control, but the application is still slower than it was on premises?
This happens when your application is spending its time sequentially 'waiting' for every request/response to complete instead of having multiple processes running in parallel. An example can be a script based on [Cursors (Transact-SQL)](https://docs.microsoft.com/en-us/sql/t-sql/language-elements/cursors-transact-sql?view=sql-server-ver15).

Here, every call between compute and storage introduces a small delay (latency) that is impacting the total execution time of the script. This delay adds up quickly: 1 million operations x 1 millisecond latency = 16 minutes and 40 seconds of execution time, excluding any other processing that may be required. 

Fortunately, Azure and SQL Server support different types of storage with different latency characteristics: 
- Using Blob storage directly (Latency based on network)
- Using Premium SSD (Latency of 5-10ms)
- Using Ultra Disks (latency under 1ms)
- Using the Local SSD (fastest; latency close to 0ms)

Premium Disks also supports different caching strategies that leverage local memory and local SSD. These strategies are [None, ReadOnly, ReadWrite](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/premium-storage-performance#disk-caching)and will influence your test results. These strategies are not available for the other storage options.

## Test approach
To illustrate the impact of latency on a sequential / SQL cursor-based script, the [PerformanceTest.sql](Scripts/PerformanceTest.sql) script is used. Note that this script is specific to validating the impact of latency. 

A new SQL Server VM is provisioned for every test, using the steps defined here (https://docs.microsoft.com/en-us/azure/virtual-machines/windows/sql/virtual-machines-windows-sql-server-storage-configuration).

## Results
> **These results give an anecdotal and informal indication of current execution times. These test results should not be considered out of this context**  

### Using Blob storage:
|     | SQL VM (D2s_v3, Blob storage) | 
| --- | --- |
|     |  **1 P30 disk, ReadOnly cache**  |
| INSERT | 00h53m08s |
| UPDATE | 00h53m08s |
| DELETE | 00h53m11s |

> Considerations: In this model, the IOPS and throughput available are shared within the storage account and the number of storage accounts within an Azure Subscription is limited. Read and write operations are billed separately. 

### Using Premium Storage:
|     | SQL VM (D2s_v3, Premium Disks) | | |
| --- | --- | --- | --- |
|     |  **1 P30 disk, ReadOnly cache**  | **1 P30 disk, ReadWrite cache** | **2x P30 disk /w Write Accelerator** |
| INSERT | 01h03m38s | 00h46m35s | 00h40m02s |
| UPDATE | 01h02m12s | 00h50m33s | 00h44m51s |
| DELETE | 01h01m36s | 00h51m39s | 00h44m08s |

> Considerations: The second measurements are against Microsoft recommendations. Guidance is to use ReadOnly caching for SQL Server workloads. 

### Using Ultra Disk Storage:
|     | SQL VM (D2s_v3, Ultra Disks) | |
| --- | --- | --- |
|     |  **2x 15000 IOPS / 250MiBps**  | **2x 800 IOPS / 100MiBps** | 
| INSERT | 00h12m49s | 00h20m28s |
| UPDATE | 00h13m33s | 00h20m30s |
| DELETE | 00h13m15s | 00h20m29s |

> Observation: Disk configurations have been oversized for the test, to ensure the limits would be driven by the application - not the infrastructure. Based on the monitoring, IOPS peaked at 1300 and Throughput at 50MBps. 

### Using Local SSD
|     | SQL VM (L4s with 678 GiB Local SSD) ||
| --- | --- | --- |
|     |  **Log + Data on Local SSD** | **Log on Local SSD, P10 for data** | 
| INSERT | 00h04m29s | 00h06m28s |
| UPDATE | 00h04m48s | 00h06m30s |
| DELETE | 00h04m21s | 00h06m29s |

> CAUTION: Using the temporary disk on a single-instance setup is a guaranteed way to suffer from data loss, system unavailability and other disaster scenarios when used in your production environment. This setup is not suggested for any production workload and only included for reasons of completeness. 

> For this setup, a 4-core, storage-optimized VM was selected. This VM is from a previous generation and availability might be limited towards the future.  

### Using SQL Managed Instance:
|     | SQL Managed Instance | | |
| --- | --- | --- | --- |
|     |  **General Purpose**  | **Business Critical (Gen 4)** | **Business Critical (Gen 5)** |
| INSERT | 01h16m19s | 00h28m06s | 00h23m19s |
| UPDATE | 01h16m52s | 00h29m09s | 00h24m33s |
| DELETE | 01h16m55s | 00h28m23s | 00h23m49s |

> Although SQL Server Managed Instance Business Critical uses the local SSD to persist data, the timings differ dramatically from the tests that used a SQL VM and stored data on the local SSD. This is caused by network latency: SQL Server need to synchronously commit every single transaction on the primary and a secondary node within the cluster to guarantee data consistency. This requirement introduces additional overhead in network communication, which impacts the execution time. 

## Considerations
As shown in the test results, disk latency can have a big impact on the performance of your SQL Servers workload. There are multiple options available and for production systems, a combination of these options can give best results. 

For example: 
| Drive | Stores                       | Characteristics                              |
| ----- | ---------------------------- | -------------------------------------------- |
| C     | OS + SQL Server installation | Premium Disk with Read/Write caching enabled |
| D     | TempDB                       | Local SSD, temporary storage.                |
| F     | Data Files (.mdf)            | Premium Disk with ReadOnly caching.          |
| G     | Log Files (.ldf)             | Ultra Disks for low-latency writes.          |

## Recommendations
- **Availability** - Local SSDs are fast and cheap - but they do not persist data in case of a reboot, deallocation, resized or rehosted VM. Don't use this for applications that are likely to end up in production, as it will hide actual performance issues. 
- **Costs** - Ultra Disks have the benefit of being persistent and offering 99.999% avaialbility, but are more expensive than the other storage options. Monitor application behavior and resource consumption, such that performance and costs can be balanced.   
- **Backup** - Disk backups are not recommended for SQL Server workloads. Azure Backup offers centralized backup management, but does not support Ultra Disks at this moment. Backups can be made via SQL Server's Automated Backup functionality, which is configured via SQL Server or the SQL Server resource provider in the Azure portal. 
- **Business Continuity / Disaster Recovery** - Azure Site Recovery does not support Ultra Disks for Azure-to-Azure failover, and defining it as a physical server in ASR results in inaccessible volumes after failover. A successful Disaster Recovery Strategy and the corresponding Recovery Point Objective (RPO) and Recovery Time Objective (RTO) should be based on the restoration of a backup. 
