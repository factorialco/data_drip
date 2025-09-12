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
  
  # Optional: Sleep time between batches in seconds (default: 0.1)
  DataDrip.sleep_time = 0.5
end
```

### Configuration Options Explained

- **`backfiller_class`**: The ActiveRecord model that represents the user running backfills. This model will be referenced in the `data_drip_backfill_runs` table to track who initiated each backfill.

- **`backfiller_name_attribute`**: The attribute on your backfiller model that contains the user's display name. This is used in the web interface to show who is running or has run backfills.

- **`current_backfiller_method`**: The method name that your base controller uses to get the currently authenticated user. DataDrip controllers will call this method to determine who is creating backfills.

- **`base_controller_class`**: The controller class that DataDrip's controllers should inherit from. This is crucial for ensuring that DataDrip controllers have access to your application's authentication, authorization, and other controller concerns.

This configuration is particularly useful when your application uses custom authentication systems, non-standard naming conventions, or when you need DataDrip to integrate with existing API controllers or admin interfaces.

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
    # Send verification email, etc.
  end
end
```

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
- Create new backfill runs
- Monitor progress and status
- View error messages and logs
- Stop running backfills
- Schedule backfills for future execution

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/factorialco/data_drip.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).