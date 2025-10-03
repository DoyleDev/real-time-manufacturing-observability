CREATE TABLE IF NOT EXISTS machine_feed_stream (
    machine_id INT PRIMARY KEY,
    machine_name TEXT,
    status TEXT,
    type TEXT,
    datetime TIMESTAMP
);

CREATE TABLE IF NOT EXISTS work_orders (                                                                                        
     id VARCHAR(50) PRIMARY KEY,                                                                                   
     machine_id VARCHAR(100) NOT NULL,                                                                             
     issue_description TEXT NOT NULL,                                                                              
     priority VARCHAR(20) NOT NULL CHECK (priority IN ('low', 'medium', 'high', 'critical')),                      
     reporter_name VARCHAR(100) NOT NULL,                                                                          
     assignee VARCHAR(100),                                                                                        
     timestamp TIMESTAMP WITH TIME ZONE NOT NULL,                                                                  
     created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,                                       
     status VARCHAR(20) NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'completed', 'cancelled'))
 );   

CREATE TABLE IF NOT EXISTS employees (                       
id SERIAL PRIMARY KEY,                          
first_name VARCHAR(100) NOT NULL,               
last_name VARCHAR(100) NOT NULL,                
email VARCHAR(255) UNIQUE,                      
department VARCHAR(100),                        
active BOOLEAN DEFAULT true,                    
created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);    

  INSERT INTO employees (first_name, last_name, email,
  department, active) VALUES
  ('Mike', 'Johnson', 'mike.johnson@company.com', 'Maintenance',
  true),
  ('Sarah', 'Wilson', 'sarah.wilson@company.com', 'Quality 
  Control', true),
  ('Tom', 'Anderson', 'tom.anderson@company.com', 'Operations',
  true),
  ('Lisa', 'Garcia', 'lisa.garcia@company.com', 'Maintenance',
  true),
  ('David', 'Chen', 'david.chen@company.com', 'Engineering',
  true),
  ('Maria', 'Rodriguez', 'maria.rodriguez@company.com',
  'Operations', true),
  ('James', 'Smith', 'james.smith@company.com', 'Maintenance',
  true),
  ('Jennifer', 'Brown', 'jennifer.brown@company.com', 'Quality 
  Control', true),
  ('Robert', 'Davis', 'robert.davis@company.com', 'Operations',
  true),
  ('Amanda', 'Miller', 'amanda.miller@company.com',
  'Engineering', true),
  ('Kevin', 'Taylor', 'kevin.taylor@company.com', 'Maintenance',
  true),
  ('Nicole', 'White', 'nicole.white@company.com', 'Operations',
  true),
  ('Christopher', 'Lee', 'chris.lee@company.com', 'Quality 
  Control', true),
  ('Rachel', 'Thompson', 'rachel.thompson@company.com',
  'Engineering', true),
  ('Daniel', 'Martinez', 'daniel.martinez@company.com',
  'Maintenance', true);
  
-- Create a function that sends notifications when machine_feed_stream table changes
CREATE OR REPLACE FUNCTION notify_machine_feed_stream_changes()
RETURNS trigger AS $$
DECLARE
    payload json;
BEGIN
    -- Create a JSON payload with the changed data
    IF TG_OP = 'DELETE' THEN
        payload = json_build_object(
            'operation', TG_OP,
            'table', TG_TABLE_NAME,
            'timestamp', EXTRACT(epoch FROM NOW()),
            'old_data', row_to_json(OLD)
        );
    ELSE
        payload = json_build_object(
            'operation', TG_OP,
            'table', TG_TABLE_NAME,
            'timestamp', EXTRACT(epoch FROM NOW()),
            'new_data', row_to_json(NEW),
            'old_data', CASE WHEN TG_OP = 'UPDATE' THEN row_to_json(OLD) ELSE NULL END
        );
    END IF;

    -- Send the notification
    PERFORM pg_notify('machine_feed_stream_changes', payload::text);

    -- Return the appropriate row
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for INSERT, UPDATE, and DELETE operations
DROP TRIGGER IF EXISTS machine_feed_stream_notify_trigger ON machine_feed_stream;

CREATE TRIGGER machine_feed_stream_notify_trigger
    AFTER INSERT OR UPDATE OR DELETE ON machine_feed_stream
    FOR EACH ROW EXECUTE FUNCTION notify_machine_feed_stream_changes();


-- Line 1 machines (9 machines)
-- Production flow: Source Sorter → Robotic Arm → Injection Molder → Valve → Injection Molder → Robotic Arm → Painter → Robotic Arm → Sorter
INSERT INTO machine_feed_stream (machine_id, machine_name, status, type, datetime) VALUES
(1, 'Source_Sorter_01_01', 'operational', 'sorter', NOW()),
(2, 'Robotic_Arm_01_01', 'operational', 'robotic_arm', NOW()),
(3, 'Injection_Molder_01_01', 'operational', 'injection_molder', NOW()),
(4, 'Valve_01_01', 'operational', 'valve', NOW()),
(5, 'Injection_Molder_01_02', 'operational', 'injection_molder', NOW()),
(6, 'Robotic_Arm_01_02', 'operational', 'robotic_arm', NOW()),
(7, 'Painter_01_02', 'operational', 'painter', NOW()),
(8, 'Robotic_Arm_01_03', 'operational', 'robotic_arm', NOW()),
(9, 'Sorter_01_01', 'operational', 'sorter', NOW());

-- Line 2 machines (7 machines)
-- Production flow: Injection Molder → Valve → Injection Molder → Robotic Arm → Painter → Robotic Arm → Sorter
INSERT INTO machine_feed_stream (machine_id, machine_name, status, type, datetime) VALUES
(10, 'Injection_Molder_02_01', 'operational', 'injection_molder', NOW()),
(11, 'Valve_02_01', 'operational', 'valve', NOW()),
(12, 'Injection_Molder_02_02', 'operational', 'injection_molder', NOW()),
(13, 'Robotic_Arm_02_01', 'operational', 'robotic_arm', NOW()),
(14, 'Painter_02_01', 'operational', 'painter', NOW()),
(15, 'Robotic_Arm_02_02', 'operational', 'robotic_arm', NOW()),
(16, 'Sorter_02_01', 'operational', 'sorter', NOW());

-- Line 3 machines (9 machines)
-- Production flow: Sorter → Robotic Arm → Injection Molder → Valve → Injection Molder → Robotic Arm → Painter → Robotic Arm → Injection Molder
INSERT INTO machine_feed_stream (machine_id, machine_name, status, type, datetime) VALUES
(17, 'Sorter_03_01', 'operational', 'sorter', NOW()),
(18, 'Robotic_Arm_03_01', 'operational', 'robotic_arm', NOW()),
(19, 'Injection_Molder_03_01', 'operational', 'injection_molder', NOW()),
(20, 'Valve_03_01', 'operational', 'valve', NOW()),
(21, 'Injection_Molder_03_02', 'operational', 'injection_molder', NOW()),
(22, 'Robotic_Arm_03_02', 'operational', 'robotic_arm', NOW()),
(23, 'Painter_03_01', 'operational', 'painter', NOW()),
(24, 'Robotic_Arm_03_03', 'operational', 'robotic_arm', NOW()),
(25, 'Injection_Molder_03_03', 'operational', 'injection_molder', NOW());

-- Line 4 machines (5 machines)
-- Production flow: Injection Molder → Valve → Robotic Arm → Painter → Sorter
INSERT INTO machine_feed_stream (machine_id, machine_name, status, type, datetime) VALUES
(26, 'Injection_Molder_04_01', 'operational', 'injection_molder', NOW()),
(27, 'Valve_04_01', 'operational', 'valve', NOW()),
(28, 'Robotic_Arm_04_01', 'operational', 'robotic_arm', NOW()),
(29, 'Painter_04_01', 'operational', 'painter', NOW()),
(30, 'Sorter_04_01', 'operational', 'sorter', NOW());