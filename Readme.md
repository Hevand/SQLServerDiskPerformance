# Performance optimization of SQL Server VMs
## Options for performance optimization
Performance is at the foundation of every successful application. When moving to the cloud, differences in underlying infrastructure characteristics may surface performance issues that were not visible on premises. 

Your strategy to address these issues depends on the current involvement of the development team:

### Scenario 1: Development team is available 
When there is a standing team that is responsible for developing or running any application, organizations can spend time and effort in identifying and addressing any performance bottleneck with an (substantial) impact on end-user experience, scalability or costs.

For starters, teams should look at the following:
- Code paths that can be optimized for performance 
- Application architecture, introducing event-based concepts / asynchronous processing
- Reducing data volumes, by being more selective in their queries / operations or by compressing data as it is being transferred over the wire 
- Bringing data and compute closer together. 
- Caching data where appropriate
- Pre-calculate data sets where appropriate 
- Evaluate sequential cross-process calls (e.g. API, database, cache) and consider combining them, to reduce network latency and avoid processes that are 'busy waiting'
- Infrastructure optimizations, balancing costs and performance. E.g. adding CPU or memory.
 

### Scenario 2: Development team is unavailable
In the real world, not every application an organization hosts will have a development team with the capacity to investigate and address performance issues by changing the application. As an example, consider legacy applications and products from a vendor. Even if the application _can_ be changed, it might not be possible or desirable to apply these changes to the production environment. 

In this situation, it will be the responsibility of the operations team to identify applicable limitations and optimize the infrastrucutre to improve performance. 

## Relational database as the cornerstone of your application
A relational database like SQL Server is a key component of many applications and a natural focus point when considering application performance improvements. 

> In my work, I have seen the focus shift from the database to the broader application, as more modern applications implement strategies that try to distribute the work more broadly and better handle unpredictable workloads. Think about caching, asynchronous processing or different data stores for read and write operations. However, even then raw storage speed continues to be important.

### SQL Server on Azure
On Azure, there are 3 different ways of running SQL Server: 
- SQL Server installed on a Windows VM (IaaS)
- SQL Database (PaaS) on the Standard / General Purpose tier
- SQL Database (PaaS) on the Premium / Business Critical tier

On the IaaS services, Microsoft offers guidance on the configuration: (https://docs.microsoft.com/en-us/azure/virtual-machines/windows/sql/virtual-machines-windows-sql-performance). When you deploy a SQL Server machine from the market place, this guidance is embedded in the default configuration. 

On the PaaS services, Microsoft offers SQL Database on a DTU-based, vCore-based or Managed Instance-based model. Here, Microsoft configures and manages the environment. The system and disk configuration is detailed here: 
- [Standard / General Purpose](https://docs.microsoft.com/en-us/azure/sql-database/sql-database-high-availability#basic-standard-and-general-purpose-service-tier-availability)
![Illustration: Standard / General Purpose](https://docs.microsoft.com/en-us/azure/sql-database/media/sql-database-high-availability/general-purpose-service-tier.png)

- [Premium / Business Critical](https://docs.microsoft.com/en-us/azure/sql-database/sql-database-high-availability#premium-and-business-critical-service-tier-availability)
![Illustration: Premium / Business Critical](https://docs.microsoft.com/en-us/azure/sql-database/media/sql-database-high-availability/business-critical-service-tier.png)

### Performance considerations for a relational database
In practice, the performance realized by a relational database will be a combination of CPU, Memory and Disk performance. As you are optimizing your application on Azure, it is important to monitor and understand the utilization of CPU, memory and disk during performance-critical operations. 

For the scope of this article, we'll limit the focus on disk performance. Although just as important, CPU and memory consumption are much more specific to your workload and harder to discuss as a general topic. 

As explained [here](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/premium-storage-performance), disk performance is qualified by:
- IOPS
- Throughput
- Latency

On Azure, both [Virtual Machines](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/sizes) and [Managed Disks](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/disk-scalability-targets) provide scalability targets and apply throttling on the amount of IOPS and Throughput available. 

> This approach differs from a typical on-premises situation with a [Storage Area Network](https://en.wikipedia.org/wiki/Storage_area_network). On a SAN, a certain maximum number of IOPS / Throughput all connected processes benefit from the maximum IOPS / Throughput that is offered - but also suffer from any 'noisy neighbour' that may exist. This unpredictable Quality of Service is undesirable on a public cloud such as Azure. Instead, Microsoft will actually allocate the capacity that is advertised to your VM / Disk. 

For IOPS and Throughput, combining the limit of the VM with the limit of the disk results in the effective IOPS and Throughput available to a SQL Server machine. Utilization can be monitored from within the Azure Portal, and if your machine is hitting these limits, you can scale up the VM and available disks (either by scaling or striping) until your application's resource utilization stays under the maximum available capacity. 

### What if IOPS and Throughput are under control, but the application is still slower than it was on premises?
Even when SQL Server stays below the limit on available IOPS and Throughput, your application may not be performing as fast as it did before. This can happen when scripts are updating individual rows, where SQL has to 'wait' for every request/response to complete before being able to continue. An example can be a script based on [Cursors (Transact-SQL)](https://docs.microsoft.com/en-us/sql/t-sql/language-elements/cursors-transact-sql?view=sql-server-ver15).

Here, every call between compute and storage introduces a small delay (latency) that is impacting the total execution time of the script. This delay adds up quickly: 1 million operations x 1 millisecond latency = 16 minutes and 40 seconds of execution time, excluding any other processing that may be required. 

> Why not having a 0ms delay? There are few considerations when thinking about public cloud. First, a public cloud is designed to minimize the Mean Time Till Recovery (MTTR) as opposed to the Mean Time Between Failures (MTBF) that is more common for on premises datacenters. Designing for MTTR implies including a level of indirection, which results in additional load balancers / network hops. Second, the public cloud is 'shared' infrastructure. Every connection needs to be authenticated, encrypted and potentially audited - where your on-premises environment was likely considered a 'trusted' environment that could do without that overhead.  

Azure and SQL Server support different types of storage with different latency characteristics: 
- Using Blob storage directly (Latency of 5-10ms)
- Using Premium SSD (Latency of 5-10ms)
- Using Ultra Disks (submillisecond latency)
- Using the Local SSD (fastest; latency close to 0ms)

Premium Disks also supports:
- Caching strategies that leverage local memory and local SSD. These strategies are [None, ReadOnly, ReadWrite](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/premium-storage-performance#disk-caching). 
- [Write Accelerator](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/how-to-enable-write-accelerator) when running on M-Series VMs. 

These features are Premium Disk-specific and not available for the other storage options.

# Performance Test Results
## Test approach
To illustrate the impact of latency on a sequential / SQL cursor-based script, the [PerformanceTest.sql](Scripts/PerformanceTest.sql) script is used. Note that this script is specific to validating the impact of latency and will have a Queue Depth of < 1; it is not designed to generate high IOPS or Throughput. 

At the start of every test, provision a new SQL Server VM using the steps defined here (https://docs.microsoft.com/en-us/azure/virtual-machines/windows/sql/virtual-machines-windows-sql-server-storage-configuration).

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
|     |  **1 P30 disk, ReadOnly cache**  | **1 P30 disk, ReadWrite cache** | **2x P30 disk, see below** |
| INSERT | 01h03m38s | 00h46m35s | 00h40m02s |
| UPDATE | 01h02m12s | 00h50m33s | 00h44m51s |
| DELETE | 01h01m36s | 00h51m39s | 00h44m08s |

> The second measurements are against Microsoft recommendations. Guidance is to use ReadOnly caching for SQL Server workloads. 

The first two test configurations are defined in the column header. 

In the third setup, I used the following disk configuration: 
- 1 P30 (Premium Managed disk, 1TB) for the Data file, ReadOnly caching
- 1 P30 (Premium Managed disk, 1TB) for the Log file, None caching 
- TempDB on the temporary drive.

### Using M-series VM, with Premium Storage with Write Acceleration
|     | SQL VM (M8ms, Premium Disks) |
| --- | --- |
|     |  **2 P30 disk**  |
| INSERT | 00h13m06s | 
| UPDATE | 00h13m06s | 
| DELETE | 00h13m07s | 

In this setup, I used the following disk configuration: 
- 1 P30 (Premium Managed disk, 1TB) for the Data file, ReadOnly caching
- 1 P30 (Premium Managed disk, 1TB) for the Log file, No caching + Write Acceleration enabled
- TempDB on the temporary drive.

### Using Ultra Disk Storage:
|     | SQL VM (D2s_v3, Ultra Disks) | |
| --- | --- | --- |
|     |  **2x 15000 IOPS / 250MiBps**  | **2x 800 IOPS / 100MiBps** | 
| INSERT | 00h12m49s | 00h20m28s |
| UPDATE | 00h13m33s | 00h20m30s |
| DELETE | 00h13m15s | 00h20m29s |

> Observation: Disk configurations have been oversized for the test, to ensure the limits would be driven by the application - not the infrastructure. Based on the monitoring, IOPS peaked at 1300 and Throughput at 50MBps. 

In this setup, I used the following disk configuration: 
- 1 100GB Ultra Disk for the Data file, ReadOnly caching
- 1 100GB Ultra Disk for the Log file, None caching
- TempDB on the temporary drive.

### Using Local SSD
|     | SQL VM (L4s with 678 GiB Local SSD) ||
| --- | --- | --- |
|     |  **Log + Data on Local SSD** | **Log on Local SSD, P10 for data** | 
| INSERT | 00h04m29s | 00h06m28s |
| UPDATE | 00h04m48s | 00h06m30s |
| DELETE | 00h04m21s | 00h06m29s |

> CAUTION: Using the temporary disk on a single-instance setup is a guaranteed way to suffer from data loss, system unavailability and other disaster scenarios when used in your production environment. This setup is not suggested for any production workload and only included for reasons of completeness. 

> For this setup, a 4-core, storage-optimized VM was selected. This VM offers a large temporary disk, but is from an older hardware generation and availability might be limited towards the future.  

### Using SQL Managed Instance:
|     | SQL Managed Instance | | |
| --- | --- | --- | --- |
|     |  **General Purpose**  | **Business Critical (Gen 4)** | **Business Critical (Gen 5)** |
| INSERT | 01h16m19s | 00h28m06s | 00h23m19s |
| UPDATE | 01h16m52s | 00h29m09s | 00h24m33s |
| DELETE | 01h16m55s | 00h28m23s | 00h23m49s |

> Although SQL Server Managed Instance Business Critical uses the local SSD to persist data, the timings differ dramatically from the tests that used a SQL VM and stored data on the local SSD. This is caused by network latency: SQL Server need to synchronously commit every single transaction on the primary and a secondary node within the cluster to guarantee data consistency. This requirement introduces additional overhead in network communication, which impacts the execution time. 

# Designing for performance, costs and maintainability
## Evaluating the test results
From the test results, it can be observed that disk latency can have a big impact on the performance of your SQL Servers workload. 

There are other things to take into consideration as well: 

|                            | Availability | Costs    | Backup                              | 
|---                         | ---          | ---      | ---                                 | 
|Blob                        | 99.999%      | $        | Azure Backup / Automated Backup     | 
|Premium                     | 99.999%      | $$       | Azure Backup / Automated Backup     | 
|Premium + Write Accelerator | 99.999%      | $$       | Azure Backup / Automated Backup     |
|Ultra Disk                  | 99.999%      | $$$      | Azure Backup / Automated Backup     |
|Local SSD                   | 99.95%*      | -        | Azure Backup / Automated Backup     |
|SQL MI                      | 99.99%       | $$       | Automated Backup                    |

Notes:
- Local SSDs are fast and cheap, but do not persist data in case of a reboot, deallocation, resized or rehosted VM. This data loss is not visible in the availability of the server, but is affecting the availability of the service as well as your RPO and RTO. **Don't use this for applications that are likely to end up in production, as it will hide actual performance issues** 
- Ultra Disk / Write-accelerated premium disk offer great speed, with the added benefit of being persistent and available. 
- Ultra Disk are more expensive than premium disks. Monitor application behavior and resource consumption, such that costs and performance can be balanced. 
- Premium Disks with Write Accelerator provide a great price per GB, but is only available on M-series machines. M-series machine have a higher entry level for the number of available vCPU, which may result in a higher TCO when including compute and SQL licensing costs.  
- SQL Server's Automated Backup works on all disk configurations. Azure Backup does not support Ultra Disks or Premium Disks that have Write Accelerator enabled. For more information around SQL Server backup, see [the documentation](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/sql/virtual-machines-windows-sql-backup-recovery)
- Business Continuity / Disaster Recovery for SQL with low RPO / RTO can be realized via [AlwaysOn, Log Shipping or Backup/Restore](https://docs.microsoft.com/en-us/azure/site-recovery/site-recovery-sql). These act on the application layer and independent on underlying storage technology. Azure Site Recovery may be considered, if the performance of Premium SSDs is sufficient and a 1 hour RPO / 2+ hour RTO is acceptable. Ultra Disks, Premium Disks with Write Acceleration and Local SSDs are not supported by ASR.  

## Conclusion
Matching your on premises SQL disk performance on a public cloud might seem challenging, but for most workloads there are options available that will deliver performance on the cloud that is appropriate for individual workloads and better in terms of scalabililty and predictability / reducing the impact of noisy neighbours.

For individual workloads, combinations of these approaches can give better results: 

For example, the following configuration combines the faster Ultra disk for SQL Log files with a more cost-effective Premium disk for SQL data files: 

| Drive | Stores                       | Characteristics                              |
| ----- | ---------------------------- | -------------------------------------------- |
| C     | OS + SQL Server installation | Premium Disk with Read/Write caching enabled |
| D     | TempDB                       | Local SSD, temporary storage.                |
| F     | Data Files (.mdf)            | Premium Disk with ReadOnly caching.          |
| G     | Log Files (.ldf)             | Ultra Disks for low-latency writes.          |
