
using Amazon.SQS.Model;
using Amazon.SQS;
using SendMessages;
using Newtonsoft.Json;

string? appqueue = Environment.GetEnvironmentVariable("SQS_Q");
string? account = Environment.GetEnvironmentVariable("ACCOUNT");
string? region = Environment.GetEnvironmentVariable("AWS_REGION");

string queueURL = "https://sqs." + region + ".amazonaws.com/" + account+ "/" +appqueue;

Console.WriteLine(queueURL);
//--env-file ./config.env
var sqsClient = new AmazonSQSClient();

for (int i=1; i<=5;i++)
{
    Order order=new Order();
    order.orderId = i;
    order.productName = $"Product{i}";
    order.quantity = (i * 5);
    await SendMessage(sqsClient,queueURL, JsonConvert.SerializeObject(order));
}

static async Task SendMessage(
      IAmazonSQS sqsClient, string queueUrl, string messageBody)
{
    SendMessageResponse msgResponse =
      await sqsClient.SendMessageAsync(queueUrl, messageBody);
      Console.WriteLine("Message added to queue");
}

