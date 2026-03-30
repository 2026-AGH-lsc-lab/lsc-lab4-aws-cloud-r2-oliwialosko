# AWS Cloud Lab — Serverless vs Containers: Latency and Cost Comparison

## Project Objective
The primary goal of this project is to measure latency (cold start, warm throughput, burst) and cost of three AWS execution environments — Lambda, Fargate, and EC2 — running an identical k-NN workload. The project also aims to build a cost model, find the break-even point, and make a quantified architectural recommendation.

## Challenges & Alternative Scenarios (The 403 Forbidden Error)
During the initial load testing phase, I encountered a persistent **HTTP 403 Forbidden** error when testing AWS Lambda. Because the AWS Academy environment utilizes strict, temporary session tokens, the SigV4 signing process required by the `oha` load-testing tool was continuously rejected by AWS Identity and Access Management (IAM). 

To adapt to these strict environment constraints without violating the lab's rules, I adjusted my approach. Instead of using `oha` for Lambda, with the assistance of AI chat tools, I designed alternative testing scripts using the native `aws lambda invoke` CLI command. This bypassed the SigV4 proxy issue while still allowing me to collect accurate server-side metrics directly from AWS CloudWatch. All of these alternative scripts can be found in the `loadtests/` directory.

---

## Task 1: Distance Calculation
* **Description**: The first task focused on verifying the core logic of distance calculations using AWS Lambda, EC2, and Fargate. 
* **Status**: **Success**. The function performed exactly as expected and returned the same values across all environments.
* **Results**: The complete outputs, execution logs, and metrics for this task have been recorded and are available in the `results/assignment-1-endpoints.txt` file.

---

## Task 2: Cold Start Analysis (Scenario A — Zip vs. Container)
* **Description**: This task evaluates the "Cold Start" behavior of Lambda functions packaged as standard `.zip` files versus Container images. To ensure a true cold start, the environment was kept idle for 20+ minutes. The test involved sending 30 sequential requests (1 request per second) to each Lambda variant. 

### Client vs. Server Time Analysis 
When analyzing the results, there is a noticeable discrepancy between the execution time reported by the client and the server.
* **Server Time (AWS CloudWatch)**: This is the time measured internally by AWS. For the very first request, it includes the `Init Duration` (the time AWS needs to provision the execution environment) and the actual code execution time (`Duration`).
* **Client Time**: This is the total round-trip time experienced from my local machine. It is significantly higher because it includes the Server Time *plus* network latency (Network RTT), DNS resolution, TLS handshakes, and Lambda Function URL routing overhead.
- **Results & Graph**:

  - The visualization comparing the response times of both variants is available in `results/figures/figure1_decomposition.png`, and the raw data can be found in `results/scenario-a-*-fixed.txt`.

  - To verify the exact cold start penalty, I used AWS CLI queries to extract the `Init Duration` from CloudWatch Logs for both the `.zip` and containerized functions.

### Conclusions 
* The latency decomposition chart clearly illustrates the significant performance overhead introduced by AWS Lambda cold starts. For the initial requests, AWS takes about ~600ms to provision the environment (`Init Duration`). Once the function is "warm," this extra delay completely disappears, and the actual code execution takes only about ~80ms.
* Surprisingly, the containerized Lambda initialized slightly faster than the ZIP package in this run. This is likely due to AWS aggressively caching the base Docker image in the background.
* Due to the 403 Forbidden error with `oha`, the Network RTT was measured separately using a pure `curl` TCP handshake. The resulting delay of approximately 200-240ms is accurate and physically expected, as the requests were routed cross-continentally from Poland directly to the `us-east-1` server region in Virginia.

---

## Assignment 3: Scenario B — Warm Steady-State Throughput

**Goal:** Measure per-request latency at sustained load across all four environments.

### Latency Data
All endpoints were warmed up prior to testing. Due to AWS Academy limits, Lambda concurrency was strictly capped at 10. The table below represents the performance of all four environments across different concurrency (`c`) levels.

| Environment | Concurrency | p50 (ms) | p95 (ms) | p99 (ms) | Server avg (ms) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Lambda (zip) | c=5 | 312 | 420 | 435 | 65.2 |
| Lambda (zip) | c=10 | 313 | 421 | 436 | 66.0 |
| Lambda (container) | c=5 | 320 | 425 | 440 | 64.6 |
| Lambda (container) | c=10 | 321 | 426 | 441 | 64.3 |
| Fargate | c=10 | 894 | 1632 | 2111* | 954.2 |
| Fargate | c=50 | 4200 | 8100 | 9500* | 954.2 |
| EC2 | c=10 | 851 | 1612 | 1785* | 962.8 |
| EC2 | c=50 | 3900 | 7800 | 8900* | 962.8 |

*(\* denote significant tail latency inflation, indicating potential queueing or instability at the 99th percentile under sustained load).*

The completed table is also available in `results/figures/figure4_latancy_table.png`

### Analysis

**1. Concurrency Scaling Behavior (Lambda vs. Always-On)**
As seen in the table, Lambda's p50 latency stays almost completely flat when concurrency increases from `c=5` to `c=10` (~312ms to ~313ms). This happens because Lambda scales purely horizontally; AWS provisions a dedicated, isolated execution environment for every concurrent request, meaning requests do not compete for the same CPU cycles.
In contrast, Fargate and EC2 experience a massive p50 latency spike (jumping from ~850ms to ~4000ms) when concurrency increases from `c=10` to `c=50`. Because these environments utilize a single, fixed-capacity instance/task (e.g., a `t3.small` with 2 vCPUs), the sudden influx of 50 concurrent requests causes severe resource contention and thread queuing. 

**2. Server-side vs. Client-side Latency Discrepancy**
There is a massive difference between Lambda's `Server avg` (~65ms) and the client-side `p50` (~312ms). This discrepancy of roughly ~240ms is almost entirely caused by physical geographic limitations. The client-side tests were executed from a local machine in Poland, while the AWS resources were hosted in the `us-east-1` (N. Virginia) region. The cross-continent Network RTT (trans-Atlantic fiber optic transit) adds a hard physical delay to every client measurement, whereas the `Server avg` reflects purely the internal compute time within the AWS data center.

---

## Assignment 4: Scenario C — Burst from Zero

**Goal:** Evaluate system behavior when traffic spikes unexpectedly from 0 to 200 concurrent requests.

### Raw Data
* All raw data and metrics for these tests are located in the results/ directory. For the EC2 and Fargate environments, standard oha tool outputs are saved as results/scenario-c-*.txt. However, due to the strict AWS Academy IAM 403 Forbidden restrictions, testing AWS Lambda with oha was impossible. To bypass this, the Lambda tests were executed using an alternative script utilizing aws lambda invoke, and their results and statistics are saved as results/scenario-c-*-fixed.txt.

### Analysis: Burst Performance and Cold Starts
* **EC2 and Fargate:** During the burst test, EC2 handled the traffic spike most effectively, yielding a p99 latency of ~1786ms. Fargate, however, suffered from severe single-task capacity limits, resulting in a much higher p99 of ~4358ms. Both operate as always-on instances, meaning they process traffic using pre-provisioned resources, but their fixed CPU limits cause heavy queuing under a sudden burst.
* **AWS Lambda:** Lambda exhibited significantly higher latencies, with p99 reaching 7339ms for ZIP and 8295ms for the Container variant. CloudWatch logs confirmed exactly 10 cold starts for each Lambda type, perfectly matching the AWS Academy concurrency limit of `c=10`. 

**Why Lambda's burst p99 is much higher:**
When the burst arrived, AWS had to provision 10 new Lambda execution environments simultaneously. This provisioning process (`Init Duration`) added around 600ms of hard overhead to the initial requests. Furthermore, handling these simultaneous cold starts within the constrained `c=10` test environment created a massive client-side execution bottleneck, drastically inflating the perceived p99 latency for the client to over 7 seconds.

**Bimodal Distribution:**
Lambda latencies under burst exhibit a strong bimodal distribution. The first "peak" (mode) consists of the initial concurrent requests that hit the cold-start cluster, suffering from the ~600ms environment initialization penalty. The second "peak" consists of subsequent requests that are routed to the newly warmed cluster, completing extremely fast without any initialization overhead.

### SLO Assessment & The Pareto Frontier
Under a sudden traffic burst, **none of the tested architectures** met the strict Service Level Objective (SLO) of p99 < 500ms. This trade-off between monthly cost and burst tail latency is visually summarized in the `results/figures/figure3_pareto_frontier.png`. As clearly shown by the vertical red SLO line, all default configurations fall far to the right of the acceptable 500ms latency zone.

To make AWS Lambda successfully meet the p99 < 500ms SLO during a burst from zero, the architecture would need to utilize Provisioned Concurrency. By pre-warming and maintaining a pool of ready-to-use execution environments (e.g., 100-200 provisioned instances), AWS bypasses the ~600ms Init Duration cold-start penalty entirely. The burst requests would immediately execute the warm code (which takes only ~80ms), keeping the p99 well below the 500ms threshold. However, implementing Provisioned Concurrency introduces a continuous hourly cost for keeping the environments active.

---

## Assignment 5: Cost at Zero Load

**Goal:** Compute the idle cost of each environment.

### Pricing Data Source & Screenshots
*Note: Screenshots of the current AWS pricing pages for Lambda and Fargate are saved in the `results/figures/pricing-screenshots/` directory with the date visible. During the execution of this assignment, the official AWS EC2 On-Demand pricing web page experienced a loading timeout/outage. To ensure accurate calculations without delay, the standard baseline price for a Linux `t3.small` instance in the `us-east-1` region ($0.0208/hour) was verified using the official AWS Pricing API / alternative official AWS documentation fallbacks.*

**1. Hourly Idle Cost**
* **AWS Lambda:** $0.00 / hour
* **Amazon EC2 (t3.small):** $0.0208 / hour
* **AWS Fargate (0.5 vCPU, 1 GB Memory):** * vCPU: 0.5 * $0.04048 = $0.02024 / hour
    * Memory: 1 GB * $0.004445 = $0.004445 / hour
    * Total Fargate: $0.024685 / hour

**2. Monthly Idle Cost (Assuming 18 hours/day idle)**
Calculation based on 30 days per month (540 idle hours total):
* **AWS Lambda:** 540 hrs × $0.00 = **$0.00**
* **Amazon EC2:** 540 hrs × $0.0208 = **$11.23**
* **AWS Fargate:** 540 hrs × $0.024685 = **$13.33**

**3. Zero Idle Cost Explanation**
**AWS Lambda** is the only environment with zero idle cost. This is because Lambda operates on a pure Serverless (pay-as-you-go) pricing model. AWS provisions compute resources only when a request is actively being processed and bills strictly for the number of requests and the execution duration (in GB-seconds). When the traffic is 0 RPS during the 18-hour idle window, Lambda consumes no resources and incurs absolutely zero charges.

---

## Assignment 6: Cost Model, Break-Even, and Recommendation

**Goal:** Compute monthly costs under a realistic traffic model, find the break-even point, and make a recommendation.

### 1. Traffic Model & Computed Costs
* **Peak:** 100 RPS × 1800s (30 min) = 180,000 req/day
* **Normal:** 5 RPS × 19800s (5.5 hrs) = 99,000 req/day
* **Total Monthly Requests (30 days):** 8,370,000 requests/month (Average ~3.23 RPS)

**Computed Monthly Cost per Environment:**
* **EC2 (Always-on):** $0.0208 × 24h × 30d = **$14.98 / month**
* **Fargate (Always-on):** $0.024685 × 24h × 30d = **$17.77 / month**
* **Lambda (p50 = 0.312s, 0.5 GB memory):**
    * Requests Cost: 8.37M × ($0.20/1M) = $1.67
    * Compute Cost: 8,370,000 req × 0.312s × 0.5 GB × $0.0000166667 = $21.76
    * Total Lambda Cost: **$23.43 / month**

### 2. Break-even RPS (Lambda vs. Fargate)
To find when Lambda becomes more expensive than Fargate ($17.77/month), we solve for the number of requests using our measured p50 duration (0.312s):
* Cost per single Lambda request: `($0.20 / 1,000,000) + (0.312s × 0.5GB × $0.0000166667) = $0.0000028`
* Requests needed to reach $17.77: `$17.77 / $0.0000028 = 6,346,428 requests/month`
* Convert to RPS: `6,346,428 / (30 days × 24h × 3600s) = 2.45 RPS`
* **Result:** Lambda becomes more expensive than Fargate when the average steady-state traffic exceeds **2.45 RPS**.

*(Note: The Cost vs. RPS line chart visually illustrating this break-even analysis is saved in the `results/figures/figure2_cost_vs_rps.png`).*

### 3. Recommendation and SLO Analysis

**Primary Environment Recommendation**
Given the strict Service Level Objective (p99 < 500ms) and the specified daily traffic model (18 hours of zero traffic, 5.5 hours at 5 RPS, and a predictable 30-minute peak of 100 RPS), my definitive recommendation is to provision an **Amazon EC2 (t3.small)** environment.

*Justification based on measurements:*
Based on Scenario B measurements, the Lambda handler duration (p50) is relatively high at 312ms. Because AWS Lambda bills per millisecond of execution, this high duration pushes the break-even point to just 2.45 RPS. Since our traffic model averages ~3.23 RPS, Lambda becomes the most expensive option at $23.43/month. As demonstrated by the Pareto Frontier analysis (Figure 3), EC2 `t3.small` dominates the other architectures by providing both the most cost-effective baseline at $14.98/month and the lowest burst tail latency (p99 = 1786ms), while Fargate suffered from severe queuing (p99 = 4358ms) and Lambda was heavily penalized by cold starts (p99 = 7339ms).


**SLO Compliance & Required Architectural Changes**
Out of the box, does the EC2 environment meet the strict rule of keeping 99% of responses under 500ms? **No.** When 100 requests hit the single `t3.small` server all at once during the daily peak, it simply cannot process them fast enough. The requests pile up in a queue, pushing the delay up to 1.78 seconds.

To fix this and successfully meet the 500ms goal, we need to add a Load Balancer (ALB) and set up Auto Scaling (ASG). Since we know exactly when the 30-minute traffic spike happens every day, we can use a "Scheduled Scaling Policy." This simply means telling AWS to automatically turn on a few extra EC2 servers 10 minutes before the rush hour starts. This way, the servers are ready and waiting, so no user gets stuck in a queue.

**Analysis of Rejected Alternatives**

Why not AWS Lambda? To make Lambda meet the 500ms SLO during the 100 RPS burst, we would have to eliminate the 7.3-second cold starts by enabling Provisioned Concurrency for at least 100 execution environments. Maintaining 100 warm environments 24/7 would incur massive hourly charges, completely invalidating the financial benefits of the Serverless model and making it astronomically more expensive than EC2.

Why not AWS Fargate? Fargate requires a similar Auto Scaling setup (ECS Service Auto Scaling) to handle the burst, but its baseline cost ($17.77/mo) is higher than EC2, and our load tests showed it struggles more with request queuing under sudden spikes (p99 of 4.35s vs EC2's 1.78s).