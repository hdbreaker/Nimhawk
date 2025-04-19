import { FaServer, FaClock, FaHeadphones, FaInternetExplorer, FaSkull } from "react-icons/fa"
import { getListenerString, getServerInfo } from "../modules/nimplant";
import { Grid, Title, Text, Button, Skeleton, Stack } from "@mantine/core"
import { Highlight } from "./MainLayout";
import { useState } from "react";
import ExitServerModal from "./modals/ExitServer";
import InfoCard from "./InfoCard"
import type Types from '../modules/nimplant.d';

// Component for single information card (for server and implant data)
function InfoCardListServer() {
  const [exitModalOpen, setExitModalOpen] = useState(false);
  const { serverInfo, serverInfoLoading, serverInfoError } = getServerInfo();
  const typedServerInfo = serverInfo as Types.ServerInfo | undefined;

  // Return the actual cards
  return (
    <Stack ml="xl" mr={40} mt="xl" gap="xs">

      <ExitServerModal modalOpen={exitModalOpen} setModalOpen={setExitModalOpen} />

      <Button
        mb="sm"
        onClick={() => setExitModalOpen(true)}
        leftSection={<FaSkull />} style={{maxWidth:'200px'}}
      >
        Kill server
      </Button>

      <Title order={2}>
        Server Information
      </Title>

      <Grid columns={2} gutter="lg">
        <Grid.Col span={{ xs: 2, md: 1}}>
          <InfoCard icon={<FaServer size='1.5em' />} content={
            <Skeleton visible={!typedServerInfo}>
              <Text>Connected to Server {' '}
                <Highlight>{typedServerInfo?.name}</Highlight>
                {' '}at{' '}
                <Highlight>{typedServerInfo && `http://${typedServerInfo.config.managementIp}:${typedServerInfo.config.managementPort}`}</Highlight>
              </Text>
            </Skeleton>
          } />
        </Grid.Col>

        <Grid.Col span={{ xs: 2, md: 1}}>
          <InfoCard icon={<FaHeadphones size='1.5em' />} content={
            <Skeleton visible={!typedServerInfo}>
              <Text>Listener running at <Highlight>{typedServerInfo && getListenerString(typedServerInfo)}</Highlight></Text>
            </Skeleton>
          } />
        </Grid.Col>
      </Grid>


      <Title order={2} pt={20}>
        Implant Profile
      </Title>

      <Grid columns={2} gutter="lg">
        <Grid.Col span={{ xs: 2, md: 1}}>
          <InfoCard icon={<FaClock size='1.5em' />} content={
            <Skeleton visible={!typedServerInfo}>
              <Text>
                Implants sleep for {' '}
                <Highlight>{typedServerInfo?.config?.sleepTime}</Highlight>
                {' '}seconds (
                <Highlight>{typedServerInfo?.config?.sleepJitter}%</Highlight>
                {' '}jitter) by default. Kill date is{' '}
                <Highlight>{typedServerInfo?.config?.killDate}</Highlight>
              </Text>
            </Skeleton>
          } />
        </Grid.Col>

        <Grid.Col span={{ xs: 2, md: 1}}>
          <InfoCard icon={<FaInternetExplorer size='1.5em' />} content={
            <Skeleton visible={!typedServerInfo}>
              <Text>
                Default Implant user agent: <Highlight>{typedServerInfo?.config?.userAgent}</Highlight>
              </Text>
            </Skeleton>
          } />
        </Grid.Col>
      </Grid>
    </Stack>
  )
}

export default InfoCardListServer