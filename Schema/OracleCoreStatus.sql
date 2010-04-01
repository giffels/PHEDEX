/*

=pod

=head1 NAME

Status - PhEDEx snapshot and historical statics, and logs

=head1 DESCRIPTION

Status tables come in three general types: snapshot tables, history
tables, and log tables.

Snapshot tables begin with C<t_status_> and describe some aspect of
the system at a single point in time, which is approximately the
present.  These tables are used to efficiently present aggregate
statistics to the user, for example via the web site.

History tables begin with C<t_history_> and contain time-ordered
statistics which should be saved forever.  These tables are used to
generate time-based plots of system, node, or link behavior.

Snapshot and history tables contain data-anonymous statistics.  They
describe counts of files or bytes, but not which files, blocks, or
datasets the statistics refer to.

Log table begin with C<t_log_> and contain more detailed statistics
that are identified by some data item as well as a timestamp.  Both
time-ordered and snapshot-type data can be derieved from these.

=head1 TABLES

=head2 t_history_link_events

This history table stores per-link file and byte counts for various
transfer I<events>.  The events occur at a single point in time, and
the statistics of events are aggregated into variable-width bins
C<timewidth> wide.

=over

=item t_history_link_events.timebin

=item t_history_link_events.timewidth

=item t_history_link_events.from_node

=item t_history_link_events.to_node

=item t_history_link_events.priority

=item t_history_link_events.avail_files

=item t_history_link_events.avail_bytes

=item t_history_link_events.done_files

=item t_history_link_events.done_bytes

=item t_history_link_events.try_files

=item t_history_link_events.try_bytes

=item t_history_link_events.fail_files

=item t_history_link_events.fail_bytes

=item t_history_link_events.expire_files

=item t_history_link_events.expire_bytes

=back

=cut

*/

/* FIXME: Consider using compressed table here, see Tom Kyte's
   Effective Oracle By Design, chapter 7.  See also the same chapter,
   "Compress Auditing or Transaction History" for swapping partitions.
   Also test if index-organised table is good. Also, look into making
   the history tables range partitioned on their timestamp. */

create table t_history_link_events
  (timebin		float		not null,
   timewidth		float		not null,
   from_node		integer		not null,
   to_node		integer		not null,
   priority		integer		not null,
   -- statistics for timebin period from t_xfer_task
   avail_files		integer, -- became available
   avail_bytes		integer,
   done_files		integer, -- successfully transferred
   done_bytes		integer,
   try_files		integer, -- attempts
   try_bytes		integer,
   fail_files		integer, -- attempts that errored out
   fail_bytes		integer,
   expire_files		integer, -- attempts that expired
   expire_bytes		integer,
   --
   constraint pk_history_link_events
     primary key (timebin, to_node, from_node, priority),
   --
   constraint fk_history_link_events_from
     foreign key (from_node) references t_adm_node (id),
   --
   constraint fk_history_link_events_to
     foreign key (to_node) references t_adm_node (id)
  );


/* FIXME: Consider using compressed table here, see
   Tom Kyte's Effective Oracle By Design, chapter 7.
   See also the same chapter, "Compress Auditing or
   Transaction History" for swapping partitions.
   Also test if index-organised table is good. */

/* t_history_link_stats.priority:
 *   same as for t_xfer_task, see OrackeCoreTransfer
 */
create table t_history_link_stats
  (timebin		float		not null,
   timewidth		float		not null,
   from_node		integer		not null,
   to_node		integer		not null,
   priority		integer		not null,
   --
   -- statistics for t_xfer_state during/at end of this timebin
   pend_files		integer, -- all tasks
   pend_bytes		integer,
   wait_files		integer, -- tasks not exported
   wait_bytes		integer,
   cool_files		integer, -- cooling off (in error) (obsolete)
   cool_bytes		integer,
   ready_files		integer, -- exported, available for transfer
   ready_bytes		integer,
   xfer_files		integer, -- taken for transfer
   xfer_bytes		integer,
   --
   -- statistics for t_xfer_path during/at end of this bin
   confirm_files	integer, -- t_xfer_path
   confirm_bytes	integer,
   confirm_weight	integer,
   -- 
   -- statistics from t_link_param calculated at the end of this cycle
   param_rate		float,
   param_latency	float,
   --
   constraint pk_history_link_stats
     primary key (timebin, to_node, from_node, priority),
   --
   constraint fk_history_link_stats_from
     foreign key (from_node) references t_adm_node (id),
   --
   constraint fk_history_link_stats_to
     foreign key (to_node) references t_adm_node (id)
  );

/* See comments above for t_history_link_*. */
create table t_history_dest
  (timebin		float		not null,
   timewidth		float		not null,
   node			integer		not null,
   dest_files		integer, -- t_status_block_dest
   dest_bytes		integer,
   cust_dest_files	integer, -- t_status_block_dest
   cust_dest_bytes	integer,
   src_files		integer, -- t_status_file
   src_bytes		integer,
   node_files		integer, -- t_status_replica
   node_bytes		integer,
   cust_node_files	integer, -- t_status_replica
   cust_node_bytes	integer,
   miss_files		integer, -- t_status_missing
   miss_bytes		integer,
   cust_miss_files	integer, -- t_status_missing
   cust_miss_bytes	integer,
   request_files	integer, -- t_status_request
   request_bytes	integer,
   idle_files		integer, -- t_status_request
   idle_bytes		integer,
   --
   constraint pk_history_dest
     primary key (timebin, node),
   --
   constraint fk_history_dest_node
     foreign key (node) references t_adm_node (id)
  );

/* Statistics for block destinations, from t_dps_block_dest */
create table t_status_block_dest
  (time_update		float		not null,
   destination		integer		not null,
   is_custodial		char (1)	not null,
   state		integer		not null,
   files		integer		not null,
   bytes		integer		not null,
   --
   constraint pk_status_block_dest
     primary key (destination, is_custodial, state),
   --
   constraint fk_status_block_dest_node
     foreign key (destination) references t_adm_node (id)
     on delete cascade,
   --
   constraint ck_status_block_dest_cust
     check (is_custodial in ('y', 'n'))
  );

/* Statistics for file origins. */
create table t_status_file
  (time_update		float		not null,
   node			integer		not null,
   files		integer		not null,
   bytes		integer		not null,
   --
   constraint pk_status_file
     primary key (node),
   --
   constraint fk_status_file_node
     foreign key (node) references t_adm_node (id)
     on delete cascade
  );

/* Statistics for replicas. */
create table t_status_replica
  (time_update		float		not null,
   node			integer		not null,
   is_custodial		char (1)	not null,
   state		integer		not null,
   files		integer		not null,
   bytes		integer		not null,
   --
   constraint pk_status_replica
     primary key (node, is_custodial, state),
   --
   constraint fk_status_replica_node
     foreign key (node) references t_adm_node (id)
     on delete cascade,
   --
   constraint ck_status_replica_cust
     check (is_custodial in ('y', 'n'))
  );

/* Statistics for missing data. */
create table t_status_missing
  (time_update		float		not null,
   node			integer		not null,
   is_custodial		char (1)	not null,
   files		integer		not null,
   bytes		integer		not null,
   --
   constraint pk_status_missing
     primary key (node, is_custodial),
   --
   constraint fk_status_missing_node
     foreign key (node) references t_adm_node (id)
     on delete cascade,
   --
   constraint ck_status_missing_cust
     check (is_custodial in ('y', 'n'))
  );


/* Statistics for transfer requests. 
 * t_status_request.state:
 *   same as t_xfer_request, see OracleCoreTransfers
 */
 create table t_status_request
  (time_update		float		not null,
   destination		integer		not null,
   priority		integer		not null,
   is_custodial		char (1)	not null,
   state		integer		not null,
   files		integer		not null,
   bytes		integer		not null,
   --
   constraint pk_status_request
     primary key (destination, priority, is_custodial, state),
   --
   constraint fk_status_request_dest
     foreign key (destination) references t_adm_node (id)
     on delete cascade,
   --
   constraint ck_status_request_cust
     check (is_custodial in ('y', 'n'))
  );

/* Statistics for groups */
 create table t_status_group
  (time_update		float		not null,
   node			integer		not null,
   user_group		integer,
   dest_files		integer		not null, -- approved files for this group
   dest_bytes		integer		not null,
   node_files		integer		not null, -- acheived files for this group
   node_bytes		integer		not null,
   --
   constraint uk_status_group
     unique (node, user_group),
   --
   constraint fk_status_group_node
     foreign key (node) references t_adm_node (id)
     on delete cascade,
   --
   constraint fk_status_group_group
     foreign key (user_group) references t_adm_group (id)
     on delete set null
  );

/* A prediction of when a dataset will arrive at a node 

   basis: the technique used to arrive at the estimate, values are
   taken from block estimate, and the value for the dataset will be
   the value of the worst block basis.  I.e., if even one block is
   suspended, the basis is 's', if even one block is using nominal
   estimate, the basis is 'n'
*/
create table t_status_dataset_arrive
  (time_update		float		not null,
   destination		integer		not null,
   dataset		integer		not null,
   blocks		integer		not null, -- number of blocks in the dataset during this estimate
   files		integer		not null, -- number of files in the dataset during this estimate
   bytes		integer		not null, -- number of bytes in the dataset during this estimate
   avg_priority		float		not null, -- average block priority
   basis		char(1)		not null, -- basis of estimate, see above
   time_span		float		        , -- max historical vision used in a block estimate
   pend_bytes		float		        , -- max queue size in bytes used in a block estimate
   xfer_rate		float		        , -- min transfer rate used in a block estimate
   time_arrive		float		        , -- worst time predicted that a block will arrive
   --
   constraint pk_status_dataset_arrive
     primary key (destination, dataset),
   --
   constraint fk_status_dataset_arrive_dest
     foreign key (destination) references t_adm_node (id)
     on delete cascade,
   --
   constraint fk_status_dataset_arrive_ds
     foreign key (dataset) references t_dps_dataset (id)
     on delete cascade
  );

/* A prediction of when a block will arrive at a node 
   basis: the technique used to arrive at the estimate, values are:
     s : suspended      - block is suspended, arrival time cannot be estimated
     n : nominal values - used when no historical information is available
     h : history values - used when no link parameter values are available
     p : link values    - used when no router values are available
     r : routing values - used when the block is activated for routing
*/
create table t_status_block_arrive
  (time_update		float		not null,
   destination		integer		not null,
   block		integer		not null,
   files		integer		not null, -- number of files in the block during this estimate
   bytes		integer		not null, -- number of bytes in the block during this estimate
   priority		integer		not null, -- t_dps_block_dest priority
   basis		char(1)		not null, -- basis of estimate, see above
   time_span		float		        , -- historical vision used in estimate
   pend_bytes		float		        , -- queue size in bytes used in estimate
   xfer_rate		float		        , -- transfer rate used in estimate
   time_arrive		float		        , -- time predicted this block will arrive
   --
   constraint pk_status_block_arrive
     primary key (destination, block),
   --
   constraint fk_status_block_arrive_dest
     foreign key (destination) references t_adm_node (id)
     on delete cascade,
   --
   constraint fk_status_block_arrive_block
     foreign key (block) references t_dps_block (id)
     on delete cascade
  );

/* Statistics for blocks being routed . */
create table t_status_block_path
  (time_update		float		not null,
   destination		integer		not null,
   src_node		integer		not null,
   block		integer		not null,
   priority		integer		not null, -- t_xfer_path priority
   is_valid		integer		not null, -- t_xfer_path is_valid
   route_files		integer		not null, -- routed files
   route_bytes		integer		not null, -- routed bytes
   xfer_attempts	integer		not null, -- xfer attempts of routed
   time_request		integer		not null, -- min (oldest) request time of routed
   --
   constraint pk_status_block_path
     primary key (destination, src_node, block, priority, is_valid),
   --
   constraint fk_status_block_path_dest
     foreign key (destination) references t_adm_node (id)
     on delete cascade,
   --
   constraint fk_status_block_path_src
     foreign key (src_node) references t_adm_node (id)
     on delete cascade,
   --
   constraint fk_status_block_path_block
     foreign key (block) references t_dps_block (id)
     on delete cascade
  );

/* Statistics for transfer paths.
 * t_status_path.priority:
 *   same as t_xfer_path, see OracleCoreTransfers
 */
create table t_status_path
  (time_update		float		not null,
   from_node		integer		not null,
   to_node		integer		not null,
   priority		integer		not null,
   is_valid		integer		not null,
   files		integer		not null,
   bytes		integer		not null,
   --
   constraint pk_status_path
     primary key (from_node, to_node, priority, is_valid),
   --
   constraint fk_status_path_from
     foreign key (from_node) references t_adm_node (id)
     on delete cascade,
   --
   constraint fk_status_path_to
     foreign key (to_node) references t_adm_node (id)
     on delete cascade
  );

/* Statistics for transfer tasks.
 *
 * t_status_task.priority:
 *   same as for t_xfer_task, see OrackeCoreTransfer
 *
 * t_status_task.state:
 *   0 = waiting for transfer
 *   1 = exported
 *   2 = in transfer
 *   3 = finished transfer
*/
create table t_status_task
  (time_update		float		not null,
   from_node		integer		not null,
   to_node		integer		not null,
   priority		integer		not null,
   is_custodial		char (1)	not null,
   state		integer		not null,
   files		integer		not null,
   bytes		integer		not null,
   --
   constraint pk_status_task
     primary key (from_node, to_node, priority, is_custodial, state),
   --
   constraint fk_status_task_from
     foreign key (from_node) references t_adm_node (id)
     on delete cascade,
   --
   constraint fk_status_task_to
     foreign key (to_node) references t_adm_node (id)
     on delete cascade,
   --
   constraint ck_status_task_cust
     check (is_custodial in ('y', 'n'))
  );


/* File size statistics (histogram + overview). */
create table t_status_file_size_overview
  (time_update		float		not null,
   n_files		integer		not null,
   sz_total		integer		not null,
   sz_min		integer		not null,
   sz_max		integer		not null,
   sz_mean		integer		not null,
   sz_median		integer		not null
  );

create table t_status_file_size_histogram
  (time_update		float		not null,
   bin_low		integer		not null,
   bin_width		integer		not null,
   n_total		integer		not null,
   sz_total		integer		not null
  );

create table t_log_dataset_latency
  (time_update		float		not null,
   destination		integer		not null,
   dataset		integer			, -- dataset id, can be null if dataset remvoed
   blocks		integer	        not null, -- number of blocks
   files		integer		not null, -- number of files
   bytes		integer		not null, -- size in bytes
   avg_priority		float		not null, -- average priority of blocks
   time_subscription	float		not null, -- min time a block was subscribed
   first_block_create	float		not null, -- min time a block was created
   last_block_create	float		not null, -- max time a block was created
   first_block_close	float		    	, -- min time a block was closed
   last_block_close	float			, -- max time a block was closed
   first_request	float			, -- min time a block was first routed
   first_replica	float			, -- min time the first file of a block was replicated
   last_replica		float			, -- max time the last file of a block was replicated
   latency		float			, -- current latency for this dataset
   serial_suspend       float                   , -- sum of all block suspend times
   serial_latency	float			, -- sum of all block latencies for this dataset
   --
   constraint fk_status_dataset_latency_dest
     foreign key (destination) references t_adm_node (id),
   --
   constraint fk_status_block_latency_ds
     foreign key (dataset) references t_dps_dataset (id)
     on delete set null);

/* Log for block completion time . */
create table t_log_block_latency
  (time_update		float		not null,
   destination		integer		not null,
   block		integer			, -- block id, can be null if block remvoed
   files		integer		not null, -- number of files
   bytes		integer		not null, -- block size in bytes
   priority		integer		not null, -- t_dps_block_dest priority
   is_custodial		char (1)	not null, -- t_dps_block_dest custodial
   time_subscription	float		not null, -- time block was subscribed
   block_create		float		not null, -- time the block was created
   block_close		float		        , -- time the block was closed
   first_request	float			, -- time block was first routed (t_xfer_request appeared)
   first_replica	float			, -- time the first file was replicated
   last_replica		float			, -- time the last file was replicated
   last_suspend		float			, -- time the block was last observed suspended
   suspend_time		float			, -- seconds the block was suspended
   latency		float			, -- current latency for this block
   --
   constraint fk_status_block_latency_dest
     foreign key (destination) references t_adm_node (id),
   --
   constraint fk_status_block_latency_block
     foreign key (block) references t_dps_block (id)
     on delete set null,
   --
   constraint ck_status_block_latency_cust
     check (is_custodial in ('y', 'n'))
  );

/* Log for user actions - lifecycle of data at a node
   actions:  0 - request data
             1 - subscribe data
             3 - delete data
*/
create table t_log_user_action
  (time_update		float		not null,
   action		integer		not null,
   identity		integer		not null,
   node			integer		not null,
   dataset		integer,
   block		integer,
   --
   constraint uk_status_user_action
     unique (time_update, action, identity, node, dataset, block),
   --
   constraint fk_status_user_action_identity
     foreign key (identity) references t_adm_identity (id),
   --
   constraint fk_status_user_action_node
     foreign key (node) references t_adm_node (id),
   --
   constraint fk_status_user_action_dataset
     foreign key (dataset) references t_dps_dataset (id),
   --
   constraint fk_status_user_action_block
     foreign key (block) references t_dps_block (id),
   --
   constraint ck_status_user_action_ref
     check (not     (block is null and dataset is null)
            and not (block is not null and dataset is not null))
  );
  
  
   

----------------------------------------------------------------------
-- Create indices

create index ix_history_link_events_from
  on t_history_link_events (from_node);

create index ix_history_link_events_to
  on t_history_link_events (to_node);
--
create index ix_history_link_stats_from
  on t_history_link_stats (from_node);

create index ix_history_link_stats_to
  on t_history_link_stats (to_node);
--
create index ix_history_dest_node
  on t_history_dest (node);
--
create index ix_status_task_to
  on t_status_task (to_node);
--
create index ix_status_path_to
  on t_status_path (to_node);
--
create index ix_status_group_group
  on t_status_group (user_group);
--
create index ix_log_user_action_identity
  on t_log_user_action (identity);

create index ix_log_user_action_node
  on t_log_user_action (node);

create index ix_log_user_action_dataset
  on t_log_user_action (dataset);

create index ix_log_user_action_block
  on t_log_user_action (block);
--
create index ix_status_block_path_src
  on t_status_block_path (src_node);

create index ix_status_block_path_block
  on t_status_block_path (block);
--
/* Use compound index instead? */
create index ix_log_block_latency_update
  on t_log_block_latency (time_update);

create index ix_log_block_latency_dest
  on t_log_block_latency (destination);

create index ix_log_block_latency_block
  on t_log_block_latency (block);

create index ix_log_block_latency_subs
  on t_log_block_latency (time_subscription);
