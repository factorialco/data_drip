# DataDrip

DataDrip is a Rails engine that provides a robust framework for running data backfills and migrations in your Rails application. It offers a web interface to monitor, schedule and manage batch processing jobs with built-in error handling and progress tracking.

## Features

- 🔄 **Batch Processing**: Process large datasets in configurable batches to avoid memory issues
- 📊 **Web Interface**: Monitor backfill progress with a built-in dashboard
- ⏰ **Scheduled Execution**: Schedule backfills to run at specific times
- 🛡️ **Error Handling**: Comprehensive error tracking and recovery
- 🔧 **Flexible Processing**: Choose between batch-level or element-level processing
- 📈 **Progress Tracking**: Real-time progress updates and batch monitoring
- 🎯 **Scoped Processing**: Define custom scopes for targeted data processing

## Installation

Add DataDrip to your application's Gemfile:

```ruby
gem 'data_drip'
```

Then execute:

```bash
bundle install
```

Run the installation generator:

```bash
rails generate data_drip:install
```

This will:

- Mount the DataDrip engine at `/data_drip` in your routes
- Create the `app/backfills` directory
- Generate and run migrations for `data_drip_backfill_runs` and `data_drip_backfill_run_batches` tables

## Requirements

- **Ruby**: >= 3.1.0
- **Rails**: >= 7.1
- **Dependencies**:
  - `importmap-rails` >= 1.2.1
  - `stimulus-rails` >= 1.0
  - `turbo-rails`

## Configuration

DataDrip can be configured to work with your application's authentication and authorization system. While the gem works out of the box with standard Rails conventions, you may need to customize these settings to match your application's architecture.

### Setting Up the Initializer (Optional)

Create a DataDrip initializer file to customize the gem's behavior:

```ruby
# config/initializers/data_drip.rb

Rails.application.configure do
  # The model class that represents users who can run backfills
  DataDrip.backfiller_class = 'Access'  # default: "::User"

  # The attribute on the backfiller model to display the user's name
  DataDrip.backfiller_name_attribute = 'first_name'  # default: :name

  # The controller method that returns the current authenticated user
  DataDrip.current_backfiller_method = :current_access  # default: :current_user

  # The base controller class that DataDrip controllers should inherit from
  DataDrip.base_controller_class = 'ApiController'  # default: "::ApplicationController"

  # The base job class that DataDrip jobs should inherit from
  DataDrip.base_job_class = '::ApplicationJob'  # default: "ActiveJob::Base"

  # The Active Job queue for the parent Dripper job (default: ENV["DATA_DRIP_QUEUE"] or :data_drip)
  DataDrip.queue_name = :backfills

  # The Active Job queue for the child DripperChild job (default: ENV["DATA_DRIP_CHILD_QUEUE"] or :data_drip_child)
  DataDrip.child_queue_name = :backfills_child

  # The class that handles lifecycle hooks for backfill runs and batches
  DataDrip.hooks_handler_class_name = 'HookHandler'  # default: nil

  # Optional: Sleep time between batches in seconds (default: 0.1)
  DataDrip.sleep_time = 0.5
end
```

### Configuration Options Explained

- **`backfiller_class`**: The ActiveRecord model that represents the user running backfills. This model will be referenced in the `data_drip_backfill_runs` table to track who initiated each backfill.

- **`backfiller_name_attribute`**: The attribute on your backfiller model that contains the user's display name. This is used in the web interface to show who is running or has run backfills.

- **`current_backfiller_method`**: The method name that your base controller uses to get the currently authenticated user. DataDrip controllers will call this method to determine who is creating backfills.

- **`base_controller_class`**: The controller class that DataDrip's controllers should inherit from. This is crucial for ensuring that DataDrip controllers have access to your application's authentication, authorization, and other controller concerns.

- **`base_job_class`**: The base job class that DataDrip's job classes (`Dripper` and `DripperChild`) should inherit from. This allows you to use a custom job class instead of the default `ActiveJob::Base`. Useful if your application has a custom job base class with additional functionality or configuration. The class must be a subclass of `ActiveJob::Base`.

- **`queue_name`**: The Active Job queue for the parent `Dripper` job. Defaults to `ENV["DATA_DRIP_QUEUE"]` if set, otherwise `:data_drip`. Resolved dynamically at enqueue time, so changes take effect immediately without restarting workers. Can also be configured via the `DATA_DRIP_QUEUE` environment variable.

- **`child_queue_name`**: The Active Job queue for the `DripperChild` batch job. Defaults to `ENV["DATA_DRIP_CHILD_QUEUE"]` if set, otherwise `:data_drip_child`. This is separate from `queue_name` so you can route parent and child jobs to different queues for priority or resource management.

- **`hooks_handler_class_name`**: The name of the class that handles lifecycle hooks for backfill runs and batches. When configured, this class will receive callbacks when backfills change status (e.g., `after_run_completed`, `after_batch_failed`). This is useful for sending notifications, tracking metrics, or integrating with external systems. See the [Hooks](#hooks) section for more details.

This configuration is particularly useful when your application uses custom authentication systems, non-standard naming conventions, or when you need DataDrip to integrate with existing API controllers or admin interfaces.

## Hooks

DataDrip provides a powerful hooks system that allows you to respond to lifecycle events during backfill execution. Hooks are tied to status transitions and run around the action that changes the status, enabling you to integrate with external systems, send notifications, track metrics, or perform any custom logic.

### Setting Up a Global Hook Handler

The recommended approach is to create a global hook handler class that responds to lifecycle events across all backfills.

First, configure the hook handler in your initializer:

```ruby
# config/initializers/data_drip.rb
DataDrip.hooks_handler_class_name = 'HookHandler'
```

Then create your hook handler class:

```ruby
# app/services/hook_handler.rb
class HookHandler
  # Run hooks - triggered when a BackfillRun changes status or action starts
  def self.before_run_enqueued(run)
    # Called before the run is enqueued
  end

  def self.around_run_enqueued(run)
    # Called around the enqueue action
    yield
  end

  def self.after_run_enqueued(run)
    # Called when a run is enqueued for execution
    # Example: Track metrics
    Metrics.increment('backfill.enqueued', tags: { backfill: run.backfill_class_name })
  end

  def self.after_run_completed(run)
    # Called when a run completes successfully
    # Example: Send notification
    SlackNotifier.notify("Backfill #{run.backfill_class_name} completed!")
  end

  def self.after_run_failed(run)
    # Called when a run fails
    # Example: Send error alert
    ErrorTracker.notify("Backfill failed: #{run.error_message}")
  end

  # Batch hooks - triggered when a BackfillRunBatch changes status
  def self.after_batch_completed(batch)
    # Called when a batch completes
    # Example: Update progress tracking
    ProgressTracker.update(batch.backfill_run_id, batch.id)
  end
end
```

**Note:** You can implement any logic inside these hooks, such as sending Slack messages, tracking metrics in DataDog, updating external systems, or logging to custom services.

### Available Hooks

DataDrip provides hooks for both backfill runs (entire backfill execution) and batches (individual batch processing):

#### Run Hooks

These hooks receive a `BackfillRun` object as a parameter. For every status, you can define any or all of the following:

- `before_run_<status>` (runs first)
- `around_run_<status>` (wraps the action and must `yield`)
- `after_run_<status>` (runs last)

Valid statuses: `pending`, `enqueued`, `running`, `completed`, `failed`, `stopped`.
Hooks always wrap the action that performs the status transition. The `around_*` hook wraps the transition itself, and the `after_*` hook runs after the status update and after the `around_*` hook completes.

#### Batch Hooks

These hooks receive a `BackfillRunBatch` object as a parameter. For every status, you can define any or all of the following:

- `before_batch_<status>` (runs first)
- `around_batch_<status>` (wraps the action and must `yield`)
- `after_batch_<status>` (runs last)

Valid statuses: `pending`, `enqueued`, `running`, `completed`, `failed`, `stopped`.
Hooks always wrap the action that performs the status transition. The `around_*` hook wraps the transition itself, and the `after_*` hook runs after the status update and after the `around_*` hook completes.

### Per-Backfill Hooks

You can also define hooks directly in your backfill classes for backfill-specific behavior. These hooks take precedence over the global handler:

```ruby
class SendWelcomeEmails < DataDrip::Backfill
  def scope
    User.where(welcome_email_sent: false)
  end

  def process_batch(batch)
    batch.each { |user| WelcomeMailer.send_welcome(user).deliver_later }
    batch.update_all(welcome_email_sent: true)
  end

  # Backfill-specific hook
  def self.after_run_completed(run)
    AdminMailer.backfill_summary(run).deliver_now
  end

  def self.after_batch_completed(batch)
    # Track progress for this specific backfill
    Rails.logger.info("Sent #{batch.batch_size} welcome emails")
  end
end
```

### Hook Precedence

When a status change occurs, DataDrip checks for hooks in the following order:

1. **Backfill class hooks** - If the backfill class defines the hook method, it will be called
2. **Global handler hooks** - If the backfill class doesn't define the hook and a global handler is configured, the handler's method will be called

This allows you to provide default behavior in the global handler while still allowing individual backfills to override specific hooks when needed.

## Creating Backfills

Generate a new backfill:

```bash
rails generate data_drip:backfill FixUserEmails
```

You can add the --sorbet flag to implement sorbet in your backfills.

This creates a backfill class in `app/backfills/fix_user_emails.rb`:

```ruby
class FixUserEmails < DataDrip::Backfill
  # Define the scope of records to process
  def scope
    User.where(email_verified: false)
  end

  # Option 1: Process entire batches (recommended for simple updates)
  def process_batch(batch)
    batch.update_all(email_verified: true)
  end

  # Option 2: Process individual elements (for complex logic)
  def process_element(element)
    element.update!(email_verified: true)
  end
end
```

### Adding Options to Backfills

You can make your backfills configurable by adding attributes that users can set when creating a backfill run. This allows for dynamic filtering and let's you customize your backfill runs:

```ruby
class AddRoleToEmployee < DataDrip::Backfill
  # Define configurable attributes
  attribute :age, :integer
  attribute :name, :string
  attribute :department, :string
  attribute :active_only, :boolean, default: true

  def scope
    scope = Employee.where(role: nil)

    # Now you can use the attributes to filter the scope dynamically
    scope = scope.where(age: age) if age.present?
    scope = scope.where(name: name) if name.present?
    scope = scope.where(department: department) if department.present?
    scope = scope.where(active: true) if active_only

    scope
  end

  def process_batch(batch)
    batch.update_all(role: 'intern')
  end
end
```

When creating a backfill run through the form in the UI, you will see form fields for each attribute, allowing you to customize the backfill's behavior without modifying code.
This way, it's easy to create a backfill run for different scenarios with different scopes.

#### Supported Attribute Types

DataDrip supports various attribute types that automatically generate appropriate form fields:

- **`:string`** - Text input field
- **`:integer`** - Number input (whole numbers)
- **`:decimal`** / **`:float`** - Number input with decimal support
- **`:boolean`** - Checkbox
- **`:date`** - Date picker
- **`:time`** - Time picker
- **`:datetime`** - Date and time picker

### Backfill Structure

Every backfill must inherit from `DataDrip::Backfill` and implement:

1. **`scope`** - Returns an ActiveRecord relation of records to process
2. **Either `process_batch` OR `process_element`** (not both):
   - `process_batch(batch)` - Processes entire batches at once (more efficient)
   - `process_element(element)` - Processes individual records (more flexible)

### Examples

#### Simple Update (Batch Processing)

```ruby
class AddDefaultRoleToUsers < DataDrip::Backfill
  def scope
    User.where(role: nil)
  end

  def process_batch(batch)
    batch.update_all(role: 'member')
  end
end
```

## Using DataDrip

### Web Interface

Navigate to `/data_drip/backfill_runs` in your application to access the DataDrip dashboard where you can:

- View all available backfills
- Create new backfill runs with configurable options
- Monitor progress and status
- View error messages and logs
- Stop running backfills
- Schedule backfills for future execution

When creating a new backfill run, the interface dynamically generates form fields based on the attributes defined in your backfill class, making it easy to customize each run without code changes.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/factorialco/data_drip.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
